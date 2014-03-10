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

	my $sock = new IO::Socket::INET (
				LocalPort => '7070',
				Proto => 'tcp',
				Listen => 1,
				Reuse => 1,
				);
	die "Could not create socket: $!\n" unless $sock;

	while( my $new_sock = $sock->accept() ){
		my $child;

		if( ( $child = fork() ) == 0 ){
			# child process
			#print Dumper $new_sock;
			$self->socket( $new_sock );
			$self->json( new JSON::XS );
			$self->process_request();
		}
	} # end while( $new_sock = $sock->accept() ) loop
} # end recv_loop()

sub process_request {
	my( $self ) = @_;

	my $line = undef;
	my $socket = $self->socket;

	while(1){
		print "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n";
		print "SR - process_request - Top of While loop\n";
		print "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n";
		$line = $self->plain_receiver( {} );

		print "Debugging Recieved line\n";
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

	print "plain_send - length: ". length( $request ) ."\n";

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

		print "SR - Scalar recieving - checksum: $checksum\n";
		
		my %temp_request = (
			SCALAR	=> $request,
			checksum => $checksum,
		);
		$request = \%temp_request;
	}

	my ($package, $filename, $line) = caller;
	print "Called from:\n\tPackage: $package\n\tFilename: $filename\n\tLine: $line\n";
	$self->print_debug( $request );

	my $json = encode_json( $request );

#	print "Plain Send Encoded JSON\n";
#	print Dumper $json;

	print "Length of json: ". length( $json ) ."\n";

	my $socket = $self->socket;

#	print $socket "WTF BBQ\n";
#	$socket->flush();

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
			print "reading: $read_line\n";
			if( defined $read_line  ){
				chomp( $read_line );
				#last if( $line ne "" );
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

#	} # end if/else

#	print "Got Line back:\n";
#	print Dumper $line;

	if( ! defined $line ){
		return undef;
	}

	print "SR - Checking line that we've gotten:\n";
	$self->print_debug( $line );

#	if( $was_json eq "1" ){
#		return $json_req;
#	}

	chomp( $line );

#	if(
#		defined $request->{v1_operation}
#		&&
#		$request->{v1_operation} eq 'syncfile'
#	){
#		print "Raw line from syncfile:\n";
#		print Dumper $line;
#	}

	if( $line eq "0" ){
		return 0;
	}

	print "Length of recieved line: ". length( $line ) ."\n";

	return $line if( $self->short_rev eq "yes" );

	my $response = decode_json( $line );

	if(
		defined $request->{v1_operation}
		&&
		$request->{v1_operation} eq 'syncfile'
	){
#		print "Response from send:\n";
#		print Dumper $response;
#		print "Ref: ". ref( $response ). "\n";
#		print "^^^^^^^^^^^^^^^^^^^^^\n";
	}

	if( ref( $response ) eq "ARRAY" ){
		return $response;
	}

	if( defined $response->{ZERO} ){
		return 0;
	}

	if( defined $response->{SCALAR} ){

#		print Dumper $response;

		my $checksum = sha256_base64($response->{SCALAR});
		
#		print "SR - SCALAR recieved - Calculated: $checksum\n";
#		print "SR - SCALAR recieved - Transfered: ". $response->{checksum} ."\n";
		if( $checksum ne $response->{checksum} ){
			print "*** Checksum's don't match\n";
			print "*** Calculated: $checksum\n";
			print "*** Transfered: ". $response->{checksum} ."\n";
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

#	print Dumper $request;

	my $temp_req = $request;

	my $temp_delta = undef;
	my $temp_sig = undef;

	print "SenderReceiver Debug:\n";

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
		print substr( $request, 0, 400 ) ."\n";
		return;
	}

	print Dumper $temp_req;

	if( defined $temp_delta ){
		$request->{delta} = $temp_delta;
	}
	if( defined $temp_sig ){
		$request->{signature} = $temp_sig;
	}

	return;
} # end print_debug()


#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
