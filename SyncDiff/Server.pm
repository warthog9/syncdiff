#!/usr/bin/perl

package SyncDiff::Server;
$SyncDiff::Server::VERSION = '0.01';

use Moose;

extends 'SyncDiff::Forkable', 'SyncDiff::SenderReciever';

#
# Needed to communicate with other modules
#

use SyncDiff::File;
use SyncDiff::Util;
use SyncDiff::Protocol::v1;

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

	$self->recv_loop();
}; # end run_child()

sub _process_request {
	my( $self, $recv_line ) = @_;

	print "Listener got: $recv_line\n";

	my $response = undef;
	my $json_success = try {
		$response = decode_json( $recv_line );
	};

	if( ! $json_success ){
		print "JSON was malformed, ignoring - ". $recv_line ."\n";
		next;
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
		my $auth_status = $self->_check_authenticateion( $response->{hostname}, $response->{group}, $response->{key} );

		if( $auth_status == 0 ){
			return "SOCKDIE";
		}
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
		print "Primary protocol version 1 found\n";
		$self->proto(
			SyncDiff::Protocol::v1->new(
				socket => $self->socket,
				version => $response->{request_version},
				dbref => $self->dbref,
				group => $self->group,
				hostname => $self->remote_hostname,
			)
		);
		return $self->proto->getVersion();
	}

	return $self->proto->server_process_request( $response );
} # end process_request()

sub _check_authenticateion {
	my ( $self, $remote_hostname, $group, $key ) = @_;
	my $config = $self->config;

	my $group_key = $config->{groups}->{ $group }->{key};	
	print "--------------------------\n";
	print Dumper $config;
	print "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	print "Got: Group |$group| Key |$key|\n";
	print "We have |$group_key|\n";

	if( $key eq $group_key ){
		print "Auth succeeded\n";
		$self->group( $group );
		$self->remote_hostname( $remote_hostname );
		return 1;
	}

	return 0;
} # end _check_authentication()

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
