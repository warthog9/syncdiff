#!/usr/bin/perl

package SyncDiff::Client;
$SyncDiff::Client::VERSION = '0.01';

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
		isa	=> 'Str',
		);

has 'auth_token' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

# End variables

#
# Need to override this from Forkable
#

override 'run_child' => sub {
	my( $self ) = @_;

	$self->recv_loop();
}; # end run_child()

sub fork_and_connect {
	my( $self ) = @_;

	print "Client::fork_and_connect - ". $self->group ." - ". $self->groupbase ."\n";
	print Dumper $self->config_options;

	print "Client::fork_and_connect - path\n";
	print Dumper $self->groupbase_path;

	if( ! -e $self->groupbase_path ){
		die( "Path: ". $self->groupbase_path ." does *NOT* exist in group ". $self->group ." - sadly dying now.\n" );
	}

	#
	# Going chroot
	# 	everything else we need should
	# 	be in the chroot, or accessible
	# 	via pipes
	#
	chroot( $self->groupbase_path );
	chdir("/");

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
		print "Host: ". $host ."\n";
		my $ip = $self->dbref->gethostbyname( $host );
		print "Ip: ". $ip ."\n";
		my $sock = new IO::Socket::INET (
						PeerAddr => $ip,
						PeerPort => '7070',
						Proto => 'tcp',
						);
		if( ! $sock ){
			print "Could not create socket: $!\n";
			next;
		} # end skipping if the socket is broken
		print $sock "Hello World!\n";
		close( $sock );
	} # end foreach $host
} # end fork_and_connect()

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
