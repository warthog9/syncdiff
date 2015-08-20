#!/usr/bin/perl

###########################################################################
# Copyright (C) 2014  John 'Warthog9' Hawley                              #
#                         jhawley@redhat.com                              #
#                         warthog9@eaglescrag.net                         #
#                                                                         #
# This file is originally part of SyncDiff(erent).                        #
#                                                                         #
# This library is free software; you can redistribute it and/or           #
# modify it under the terms of the GNU Lesser General Public              #
# License as published by the Free Software Foundation; either            #
# version 2.1 of the License, or (at your option) any later version.      #
#                                                                         #
# This library is distributed in the hope that it will be useful,         #
# but WITHOUT ANY WARRANTY; without even the implied warranty of          #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       #
# Lesser General Public License for more details.                         #
#                                                                         #
# You should have received a copy of the GNU Lesser General Public        #
# License along with this library; if not, write to the:                  #
#    Free Software Foundation, Inc.                                       #
#    51 Franklin Street                                                   #
#    Fifth Floor                                                          #
#    Boston, MA  02110-1301                                               #
#    USA                                                                  #
#                                                                         #
# Or, see <http://www.gnu.org/licenses/>.                                 #
###########################################################################

package FileSync::SyncDiff::SenderReceiver;
$FileSync::SyncDiff::SenderReceiver::VERSION = '0.01';

use Moose;

extends qw(FileSync::SyncDiff::Forkable);

#
# Needed to communicate with other modules
#

use FileSync::SyncDiff::Util;
use FileSync::SyncDiff::Protocol::v1;

#
# Other Includes
#

use JSON::XS;
use MIME::Base64;
use IO::Socket;
use IO::Handle;
use Try::Tiny;
use Digest::SHA qw(sha256 sha256_hex sha256_base64);

#
# Debugging
#

use Data::Dumper;

# End Includes

#
# moose variables
#

has 'socket' => (
		is	=> 'rw',
		isa	=> 'IO::Socket::INET',
		);
has 'json' => (
		is	=> 'rw',
		isa	=> 'JSON::XS',
		);
has 'short_rev' => (
		is	=> 'rw',
		isa	=> 'Str',
		default	=> 'yes',
		);

#
# Ridiculous Globals (for now)
#
my $TIMEOUT = 300;

# End variables

sub recv_loop {
	my ( $self ) = @_;

	my $sock = eval {
		IO::Socket::INET->new (
			LocalPort => '7070',
			Proto => 'tcp',
			Listen => 1,
			Reuse => 1,
			);
	};
	if ( !$sock ) {
		$self->log->fatal("Could not create socket: %s", $!);
	}

	while( my $new_sock = $sock->accept() ){
		my $child;

		if( ( $child = fork() ) == 0 ){
			# child process
			$self->socket( $new_sock );
			$self->json( new JSON::XS );
			$self->process_request();
		}
		
		my $kid = undef;
		do {
			$kid = waitpid($child,0);
		} while $kid > 0;
	} # end while( $new_sock = $sock->accept() ) loop
} # end recv_loop()

sub process_request {
	my( $self ) = @_;

	my $line = undef;
	my $socket = $self->socket;

	while(1){
		$self->log->debug("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
		$self->log->debug("SR - process_request - Top of While loop");
		$self->log->debug("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
		$line = $self->plain_receiver( {} );

		$self->log->debug("Debugging Recieved line");
		$self->print_debug( $line );

		if( ! defined $line ){
			exit(1);
		}

		my $response = $self->_process_request( $line );
		$self->print_debug( $response );

		if( ! defined $response  ){
			next;
		}

		$self->plain_send( $response );

		if( $response eq "SOCKDIE" ){
			$socket->shutdown(2);
			exit(0);
		}
	} # end while() loop
} # end recv_loop()

sub send_request {
	my( $self, %request ) = @_;
	my $socket = $self->socket;

	$self->plain_send( \%request );

	return $self->plain_receiver( \%request );
} # end send_request()

sub plain_send {
	my( $self, $request ) = @_;

	$self->log->debug("plain_send - length: %s", length( $request ));

	if(
		$request eq "0"
	){
		my %temp_resp = (
			ZERO	=> "0",
		);
		$request = \%temp_resp;
	}

	my $ref_request = ref( \$request );

	if(
		! defined $ref_request
		||
		$ref_request eq "SCALAR"
		||
		$ref_request eq ""
	){
		my $checksum = sha256_base64($request);

		$self->log->debug("SR - Scalar recieving - checksum: %s",$checksum);

		my %temp_request = (
			SCALAR	=> $request,
			checksum => $checksum,
		);
		$request = \%temp_request;
	}

	my ($package, $filename, $line) = caller;
	$self->print_debug( $request );

	my $json = encode_json( $request );

	$self->log->debug("Length of json: %s", length( $json ));

	my $socket = $self->socket;

	print $socket $json ."\n";
	$socket->flush();
	print $socket "--END--\n";
	$socket->flush();
} # end plain_send()

sub plain_receiver {
	my( $self, $request ) = @_;

	my $socket = $self->socket;

	my $line = undef;
	my $read_line = undef;

	if( ! defined $socket ){
		return;
	}

	# attach a timeout to trying to listen to the
	# socket in case things take forever and we
	# should just give up and die
	my $was_json = -1;
	my $json_req = undef;
	eval {
		alarm($TIMEOUT);
		while( $read_line = <$socket> ){
			$self->log->debug("reading: %s",$read_line);
			if( defined $read_line  ){
				chomp( $read_line );
				if( 
					$read_line eq "--END--\n"
					||
					$read_line eq "--END--"
				){
					if( ! defined $line ){
						# print "SOMETHING IS WRONG IN THE PROTOCOL AND SHOULD BE LOOKED INTO\n";
						next;
					}
					$was_json = 0;
					last;
				} else {
					$line .= $read_line;
				}
			} # end if statement
			my $json = $self->json;
			my $found = 0;

			for $json_req ( $json->incr_parse( $read_line ) ){
				$found = 1;
				$was_json = 1;
				last;
			}

			last if( $found ne "0" );
		} # end while loop waiting on socket to return
		return 0;
	}; # end eval / timeout 

	if( ! defined $line ){
		return undef;
	}

	$self->log->debug("SR - Checking line that we've gotten:");
	$self->print_debug( $line );

	chomp( $line );

	if( $line eq "0" ){
		return 0;
	}

	$self->log->debug("Length of recieved line: ", length( $line ));

	return $line if( $self->short_rev eq "yes" );

	my $response = decode_json( $line );

	if( ref( $response ) eq "ARRAY" ){
		return $response;
	}

	if( defined $response->{ZERO} ){
		return 0;
	}

	if( defined $response->{SCALAR} ){

		my $checksum = sha256_base64($response->{SCALAR});

		if( $checksum ne $response->{checksum} ){
			$self->log->debug("*** Checksum's don't match");
			$self->log->debug("*** Calculated: %s",$checksum);
			$self->log->debug("*** Transfered: %s", $response->{checksum});
		}

		return $response->{SCALAR};
	}

	if( defined $response->{ARRAY} ){
		return $response->{ARRAY};
	}

	return $response;
} # end plain_receiver()

sub print_debug {
	my( $self, $request ) = @_;

	my $temp_req = $request;

	my $temp_delta = undef;
	my $temp_sig = undef;

	$self->log->debug("SenderReceiver Debug:");

	if( ref($request) eq 'HASH' ){
		if(
			defined $request->{delta}
			||
			exists $request->{delta}
		){
			$temp_delta = $request->{delta};
			$temp_req->{delta} = "<STUFF>";
		} # end delta

		if(
			defined $request->{signature}
			||
			exists $request->{signature}
		){
			$temp_sig = $request->{signature};
			$temp_req->{signature} = "<STUFF>";
		}
	} # end hash saves

	if(
		ref($request) eq 'SCALAR'
		&&
		length( $request ) > 400
	){
		$self->log->debug(substr( $request, 0, 400 ));
		return;
	}

	$self->log->debug(Dumper $temp_req);

	if( defined $temp_delta ){
		$request->{delta} = $temp_delta;
	}
	if( defined $temp_sig ){
		$request->{signature} = $temp_sig;
	}

	return;
} # end print_debug()

__PACKAGE__->meta->make_immutable;

1;
