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

package FileSync::SyncDiff::Server;
$FileSync::SyncDiff::Server::VERSION = '0.01';

use Moose;

extends 'FileSync::SyncDiff::Forkable', 'FileSync::SyncDiff::SenderReceiver';

#
# Needed to communicate with other modules
#

use FileSync::SyncDiff::File;
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

has 'auth_token' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'proto' => (
		is	=> 'rw',
		isa	=> 'Object',
		);

has 'dbref' => (
		is	=> 'rw',
		isa	=> 'Object',
		required => 1,
		);
has 'config' => (
		is	=> 'rw',
		isa	=> 'HashRef',
		required => 1,
		);
has 'group' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 0,
		);

has 'groupbase' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 0,
		);
has 'remote_hostname' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 0,
		);



# End variables

sub run {
	my( $self ) = @_;

	$self->fork();
} # end run()

#
# Need to override this from Forkable
#

override 'run_child' => sub {
	my( $self ) = @_;

	eval {
		$self->recv_loop();
	};
	if ($@) {
		print STDERR $@;
		exit(0);
	}
}; # end run_child()

sub _process_request {
	my( $self, $recv_line ) = @_;

	if( ! defined $recv_line ){
		return undef;
	}

	my $response = undef;
	my $json_success = try {
		$response = decode_json( $recv_line );
	};

	if( ! $json_success ){
		print STDERR "JSON was malformed, ignoring - ". $recv_line ."\n";
		return undef;
	}

	if(
		exists( $response->{operation} )
		&&
		$response->{operation} eq "authenticate"
		&&
		exists( $response->{group} )
		&&
		exists( $response->{key} )
		&&
		exists( $response->{hostname} )
	){
		my $auth_status = $self->_check_authentication( $response->{hostname}, $response->{group}, $response->{key} );

		print STDERR "_process_request Auth Status: $auth_status\n";

		if( $auth_status == 0 ){
			print STDERR "Socket Die, Auth really failed\n";
			return "SOCKDIE";
		}

		print STDERR "Going to return successful Authentication\n";
		return 0;
	}
	if(
		exists( $response->{operation} )
		&&
		$response->{operation} eq "request_protocol_versions"
	){
		return [ "1.0", "0.99", "2.0", "3.0", "1.1", "1.2", "fat" ];
	}

	if(
		exists( $response->{request_version} )
		&&
		$response->{request_version} > 1
		&&
		$response->{request_version} < 2
	){
		print STDERR "Primary protocol version 1 found\n";
		print STDERR Dumper $self->groupbase;
		$self->proto(
			FileSync::SyncDiff::Protocol::v1->new(
				socket => $self->socket,
				version => $response->{request_version},
				dbref => $self->dbref,
				group => $self->group,
				hostname => $self->remote_hostname,
				groupbase => $self->groupbase,
			)
		);
		return $self->proto->getVersion();
	}

	my $processed_response = $self->proto->server_process_request( $response );

	return $processed_response;
} # end process_request()

sub _check_authentication {
	my ( $self, $remote_hostname, $group, $key ) = @_;
	my $config = $self->config;

	my $group_key = $config->{groups}->{ $group }->{key};

	print STDERR "Got: Group |$group| Key |$key|\n";
	print STDERR "We have |$group_key|\n";

	if( $key eq $group_key ){
		print STDERR "Auth succeeded\n";
		$self->group( $group );
		$self->remote_hostname( $remote_hostname );

		print STDERR Dumper $config->{groups}->{ $group };
		$self->groupbase( $config->{groups}->{ $group }->{patterns}[0] );
		return 1;
	}

	return 0;
} # end _check_authentication()

__PACKAGE__->meta->make_immutable;

1;
