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

package FileSync::SyncDiff::Client;
$FileSync::SyncDiff::Client::VERSION = '0.01';

use Moose;

extends qw(FileSync::SyncDiff::Forkable);

#
# Needed to communicate with other modules
#

use FileSync::SyncDiff::File;
use FileSync::SyncDiff::Util;
use FileSync::SyncDiff::Protocol::v1;
use FileSync::SyncDiff::Log;

#
# Other Includes
#

use JSON::XS;
use MIME::Base64;
use IO::Socket;
use IO::Handle;
use IO::Socket::INET;
use LWP::UserAgent;
use URI;
use Net::Domain qw(domainname);

use Scalar::Util qw(looks_like_number);

#
# Debugging
#

use Data::Dumper;

# End Includes

#
# moose variables
#

has 'config_options' => (
		is	=> 'rw',
		isa	=> 'HashRef',
		required => 1,
		);

has 'group' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'groupbase' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'dbref' => (
		is	=> 'rw',
		isa	=> 'Object',
		required => 1,
		);

has 'groupbase_path' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'socket' => (
		is	=> 'rw',
		isa	=> 'IO::Socket::INET',
		);

has 'protocol_version' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'protocol_object' => (
		is	=> 'rw',
		isa	=> 'Object',
		);

# Logger system
has 'log' => (
		is => 'rw',
		isa => 'FileSync::SyncDiff::Log',
		default => sub {
			my $self = shift;
			return FileSync::SyncDiff::Log->new( config => $self->config );
		}
);

# End variables

#
# Need to override this from Forkable
#

override 'run_child' => sub {
	my( $self ) = @_;

	$self->recv_loop();
}; # end run_child()

#
# Signal handling - mostly for SIGALRM to handle timeout events
#

#
# SIGALRM is for dealing with timeouts
#

$SIG{ALRM} = sub {
	# Timeout handling
	#	Basically we want have the program
	#	exit at this point as something
	#	has gone hideously wrong.
	#
	#	It's possible in a future version we
	#	might have it go quiet (in the client
	#	side) and then re-try the connection.
	#
	#	The server side should pretty much just
	#	hang-up.
	exit(0);
	die; 
};

#
# Ridiculous globals
#

my $TIMEOUT = 300;

#
# Real Code beyond here
#


sub fork_and_connect {
	my( $self ) = @_;
	my $dbref = $self->dbref();

	$self->log->debug("Client::fork_and_connect - %s - %s",$self->group,$self->groupbase);
	$self->log->debug("Config options: %s",Dumper($self->config_options));

	$self->log->debug("Client::fork_and_connect - path %s", Dumper($self->groupbase_path));

	if( ! -e $self->groupbase_path ){
		$self->log->fatal( "Path: %s does *NOT* exist in group %s  - sadly dying now", $self->groupbase_path, $self->group );
	}

	#
	# Ok now we need to connect to the
	# various hosts associated with
	# this group.  There are two obvious
	# ways to do this
	#
	# (1) do them sequentially - this is 
	#     probably ok but for whatever
	#     reason it doesn't seem to be
	#     the best option
	# (2) run them all in their own 
	#     process and chew up all the
	#     bandwidth
	#
	# considering that we are already
	# potentially transfering files in
	# parallel I think I'm going to
	# play it safe and do it sequentially
	# *FOR NOW*
	#
	# I.E. this should be a config option
	# at some point in the future
	#

	foreach my $host ( @{ $self->config_options->{groups}->{ $self->group }->{host} } ){
		$self->log->debug("Host: %s", $host->{host});
		my $ip = $self->dbref->gethostbyname( $host->{host} );
		$self->log->debug("Ip: %s", $ip);
		my $port =  $host->{port} || '7070';

		if ( $host->{proto} && $host->{proto} =~ /^http[s]?$/ ) {
			my %agent_opt = ( timeout => 10 );
			my $ua  = LWP::UserAgent->new(%agent_opt);
			my $uri = URI->new();

			my $params = {
				key => $self->config_options->{groups}->{ $self->group }->{key},
				include => $self->groupbase_path,
				host => inet_ntoa(inet_aton(domainname())),
			};
			$uri->scheme($host->{proto});
			$uri->host($host->{host});
			$uri->port($host->{port});

			my $response = $ua->post($uri,$params);
			if ( $response->is_success ) {
				$self->log->info("Success response from %s", $host->{host});
			}
			else {
				my $msg = $response->message;
				$self->log->error("Failed response from %s : %s", $host->{host}, $msg);
				next;
			}

			my $json = decode_json($response->decoded_content);
			if ( $json ) {
				$ip   = $json->{host} ? $json->{host} : $ip;
				$port = $json->{port} ? $json->{port} : $port;
			}

		}

		#
		# Going chroot
		# 	everything else we need should
		# 	be in the chroot, or accessible
		# 	via pipes
		#
		chroot( $self->groupbase_path );
		chdir("/");

		my $sock = eval {
			IO::Socket::INET->new(
				PeerAddr => $ip,
				PeerPort => $port,
				Proto => 'tcp',
				);
		};
		if( ! $sock ){
			$self->log->warn("Could not create socket: %s", $!);
			next;
		} # end skipping if the socket is broken

		$sock->autoflush(1);

		$self->socket( $sock );

		#
		# We need to authenticate against the server
		# before we try to negotiate a protocol
		#

		my $auth_status = $self->authenticate_to( $dbref->getlocalhostname, $self->group, $self->config_options->{groups}->{ $self->group }->{key} );

		$self->log->debug("Auth Status: %s",$auth_status);

		if( $auth_status == 0 ){
			$self->log->info("Authentication failed for %s", $host->{host});
			$sock->shutdown(2);
			next;
		}

		#
		# Ok, here we get the proper protocol all worked out
		#
		$self->request_protocol_versions( $host->{host} );

		#
		# Next we should let the protocol object take over
		# and run with the connection.  It's not our job
		# (here) to tell it what / how to do things.  If we 
		# do we run the risk of making future protocol changes
		# complex or a major issue.  Pass it on and let go
		#

		$self->log->debug("Protocol should be setup");
		my $protocol_obj = $self->protocol_object();

		$protocol_obj->client_run(); 

		close( $sock );
	} # end foreach $host
} # end fork_and_connect()

sub authenticate_to {
	my( $self, $local_hostname, $group, $key ) = @_;

	my %request = (
		'operation'	=> 'authenticate',
		'group'		=> $group,
		'key'		=> $key,
		'hostname'	=> $local_hostname,
	);

	my $auth_status = $self->basic_send_request( %request );

	$self->log->debug("authenticate_to status: %s",Dumper ($auth_status));

	if( $auth_status == 0 ){
		return 1;
	}

	return 0;
} # end request_protocol_version()

sub request_protocol_versions {
	my( $self, $host ) = @_;

	my %request = (
		'operation'	=> 'request_protocol_versions',
	);

	$self->log->debug("Going to request Protocol Versions:");

	my $versions = $self->basic_send_request( %request );

	$self->log->debug("Got Back Version: %s",Dumper ($versions));

	my $highest_proto_supported = "1.99";
	my $proto_to_use = 0;

	foreach my $ver ( @{$versions} ){
		$self->log->debug("Version: %s", $ver);

		if( ! looks_like_number($ver) ){
			$self->log->warn("*** %s is not a version number",$ver);
			next;
		}

		if(
			$ver <= $highest_proto_supported
			&&
			$ver >= $proto_to_use
		){
			$proto_to_use = $ver;
			$self->log->debug("Currently selected Protocol Version: %s", $ver);
		}
	} # end foreach $ver

	$self->protocol_version( $proto_to_use );

	my $protocol_obj;

	if(
		$proto_to_use >= 1.0
		&&
		$proto_to_use < 2.0
	){
		$protocol_obj = FileSync::SyncDiff::Protocol::v1->new( socket => $self->socket, version => $proto_to_use, dbref => $self->dbref, group => $self->group, hostname => $host, groupbase => $self->groupbase, log => $self->log );
	}

	$protocol_obj->setup();

	$self->protocol_object( $protocol_obj );
} # end request_protocol_version()

sub basic_send_request {
	my( $self, %request ) = @_;

	my $json = encode_json( \%request );

	my $socket = $self->socket;

	print $socket $json ."\n";
	$socket->flush();
	print $socket "--END--\n";
	$socket->flush();

	my $line = undef;
	my $read_line = undef;

	# attach a timeout to trying to listen to the
	# socket in case things take forever and we
	# should just give up and die
	eval {
		alarm($TIMEOUT);
		while( $read_line = <$socket> ){
			if( defined $read_line  ){
				chomp( $read_line );
				#last if( $line ne "" );
				if( 
					$read_line eq "--END--\n"
					||
					$read_line eq "--END--"
				){
					last;
				} else {
					$line .= $read_line;
				}
			} # end if read_line
		} # end while loop waiting on socket to return
		return 0;
	}; # end eval / timeout 

	if( ! defined $line ){
		return undef;
	}

	chomp( $line );

	$self->log->debug("Basic send receive line back:");
	$self->log->debug(Dumper $line);

	if( $line eq "0" ){
		return 0;
	}

	my $response = decode_json( $line );

	$self->log->debug('Response: %s', Dumper ($response));
	$self->log->debug("Ref: %s", ref( $response ));

	if( ref( $response ) eq "ARRAY" ){
		return $response;
	}

	if( defined $response->{ZERO} ){
		return 0;
	}

	if( defined $response->{SCALAR} ){
		return $response->{SCALAR};
	}

	if( defined $response->{ARRAY} ){
		return $response->{ARRAY};
	}

	return $response;
} # end send_request()

__PACKAGE__->meta->make_immutable;

1;
