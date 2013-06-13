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
			$self->process_request( $new_sock );
		}
	} # end while( $new_sock = $sock->accept() ) loop
} # end recv_loop()

sub process_request {
	my( $self, $socket ) = @_;
	my $recv_line = undef;

	while( $recv_line = <$socket> ){
		print "Listener got: $recv_line\n";

		#if( $self->auth_token()
	}
} # end process_request()

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
