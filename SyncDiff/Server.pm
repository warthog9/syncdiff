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
		$self->proto( SyncDiff::Protocol::v1->new( socket => $self->socket, version => $response->{request_version}, dbref => $self->dbref ) );
		return $self->proto->getVersion();
	}

	return $self->proto->server_process_request( $response );
} # end process_request()

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
