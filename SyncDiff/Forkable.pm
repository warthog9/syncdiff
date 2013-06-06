#!/usr/bin/perl

package SyncDiff::Forkable 0.01;
use Moose;

use SyncDiff::Util;

#
# Needed for dealing with DB stuff
#

use IO::Socket;

#
# Debugging
#

use Data::Dumper;

# End includes

#
# moose variables
#

has 'PARENT_IPC' => (
		is	=> 'ro',
		isa	=> 'GlobRef',
		writer	=> '_write_parent_ipc',
		);

has 'CHILD_IPC' => (
		is	=> 'ro',
		isa	=> 'GlobRef',
		writer	=> '_write_child_ipc',
		);

has 'pid' => (
		is	=> 'ro',
		isa	=> 'Str',
		writer	=> '_write_pid',
		);
# End variables

sub fork {
	my( $self ) = @_;

	#
	# Set up the Communications socket for the
	#	forked process
	#

	my $PARENT_IPC;
	my $CHILD_IPC;
	my $pid;

	socketpair(
			$CHILD_IPC,
			$PARENT_IPC,
			AF_UNIX,
			SOCK_STREAM,
			PF_UNSPEC
		) || die "DB:fork() - socketpair error $!";
	$CHILD_IPC->autoflush(1);
	$PARENT_IPC->autoflush(1);

	#
	# Actually deal with the fork
	#

	if( ( $pid = fork() ) == 0 ){
		# child process

		# Save out the important bits
		$self->_write_parent_ipc( $PARENT_IPC );

		# close the child IPC
		#	(I.E. I don't need to talk to myself)
		close $CHILD_IPC;

		#
		# At this point we are independent, and we are
		# going to jump into the recv loop to process
		# incoming requests.
		#
		$self->run_child();
		exit(0);
	} else {
		# parent process

		# Save out the important bits
		$self->_write_child_ipc( $CHILD_IPC );
		$self->_write_pid( $pid );

		# close the child IPC
		#	(I.E. I don't need to talk to myself)
		close $PARENT_IPC;
	} # end forking if/else
} # end fork()

sub run_child {
	my( $self ) = @_;

	return;
}

#no moose;
__PACKAGE__->meta->make_immutable;

1;
