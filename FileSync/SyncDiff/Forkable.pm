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

package SyncDiff::Forkable;
$SyncDiff::Forkable::VERSION = '0.01';
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
