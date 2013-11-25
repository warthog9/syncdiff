#!/usr/bin/perl

package SyncDiff::Server;
$SyncDiff::Server::VERSION = '0.01';

use Moose;

extends qw(SyncDiff::Forkable);

#
# Needed to communicate with other modules
#

use SyncDiff::File;
use SyncDiff::Util;

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
		isa	=> 'Str',
		);

has 'auth_token' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'proto' => (
		is	=> 'rw',
		isa	=> 'Object',
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
			print Dumper $new_sock;
			$self->process_request( $new_sock );
		}
	} # end while( $new_sock = $sock->accept() ) loop
} # end recv_loop()

sub process_request {
	my( $self, $socket ) = @_;

	my $line = undef;

	print Dumper $socket;

	if( ! defined $socket ){
		return;
	}

	while( $line = <$socket> ){
		chomp($line);

		print "Server got:\n";
		print Dumper $line;

		my $response = $self->_process_request( $line );

		if(
			$response eq "0"
		){
			my %temp_resp = (
				ZERO	=> "0",
			);
			$response = \%temp_resp;
		}

##		print "Reference check: ". ref( $response ) ."\n";
##		print Dumper $response;

		my $ref_resp = ref( \$response );

		if(
			! defined $ref_resp
			||
			$ref_resp eq "SCALAR"
			||
			$ref_resp eq ""
		){
			my %temp_resp = (
				SCALAR	=> $response,
			);
			$response = \%temp_resp;
		}

		my $json_response = encode_json( $response );

		print $socket $json_response ."\n";
	}
} # end recv_loop()


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
		$self->proto = SyncDiff::Protocol::v1->new( socket => $self->socket, version => $response->{request_version} );
	}
} # end process_request()

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
