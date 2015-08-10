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

package FileSync::SyncDiff::Scanner;
$FileSync::SyncDiff::Scanner::VERSION = '0.01';
use Moose;

extends qw(FileSync::SyncDiff::Forkable);

# SyncDiff parts I need

use FileSync::SyncDiff::Config;
use FileSync::SyncDiff::File;
use FileSync::SyncDiff::DB;
use FileSync::SyncDiff::Util;
use FileSync::SyncDiff::Log;

#
# Needed for the file scanning
#

use File::Find;
use IO::File;
use IO::Socket;
use IO::Handle;
use IO::Select;
use Sys::Hostname;
use Digest::SHA qw(sha256_hex);
use POSIX ":sys_wait_h";

#
# Debugging
#

use Data::Dumper;

# End includes

#
# Local variables
#

has 'dbref' => (
	is		=> 'rw',
	isa		=> 'Object',
	required	=> 1,
	);

has 'group' => (
	is		=> 'rw',
	isa		=> 'Str',
	required	=> 1,
	);

has 'groupbase' => (
	is		=> 'rw',
	isa		=> 'Str',
	required	=> 1,
	);

has 'current_transaction_id' =>(
	is		=> 'rw',
	isa		=> 'Str',
	);

has 'scan_count' => (
	is		=> 'rw',
	isa		=> 'Int',
	);

# Logger system
has 'log' => (
		is => 'rw',
		isa => 'FileSync::SyncDiff::Log',
		default => sub {
			return FileSync::SyncDiff::Log->new();
		}
);

#
# End 
#

sub fork_and_scan {
	my( $self ) = @_;

	$self->fork();
} # end fork_and_scan()

#
# Need to override this from Forkable
#
override 'run_child' => sub {
	my( $self ) = @_;

	$self->log->debug("About to chroot");

	chroot( $self->groupbase );
	chdir( "/" );

	$self->log->debug("chrooted");

	$self->scan();

}; # end run_child();

sub full_scan {
	my ( $self, $config, $dbconnection, $log ) = @_;

	$log ||= $self->log;

	my %running_scanners = ();

	foreach my $group_name ( keys %{ $config->config->{groups} } ){
		$log->debug("run only scan group: %s", $group_name);
		
		my $scanner = undef;

		foreach my $base_path ( @{ $config->config->{groups}->{$group_name}->{patterns} } ){
			$scanner = FileSync::SyncDiff::Scanner->new( dbref => $dbconnection, group => $group_name, groupbase => $base_path );
			$scanner->fork_and_scan();
			$running_scanners{$group_name}{$base_path} = $scanner;
		} # end foreach $base_path
	} # end foreach $group_name

	my $kid;

	foreach my $group_name (keys %running_scanners) {
		$log->debug("Group Wait: %s",$group_name);
		foreach my $base_path ( keys %{ $running_scanners{$group_name} } ){
			$log->debug("Base Path: %s", $base_path);
			my $pid = $running_scanners{$group_name}{$base_path}->pid();
			$log->debug("Pid: %s",$pid);
			$kid = waitpid( $pid, 0); 
		}
	}

	$dbconnection->clean_stop();

	do {
		$kid = waitpid(-1,0);
	} while $kid > 0;

	return;
} # end full_scan()

sub scan {
	my( $self ) = @_;

	#
	# Totally an Invader Zim reference
	#
	$self->log->debug("I'm SCANNING I'm SCANNING! - %s", $$);

	$self->create_transaction_id();

	#
	# This checks the files that we *DO* have on the
	# system, we also need to check the files in the
	# database to see if they are present, if not
	# they need to be marked as deleted.
	#

	find( {
		wanted		=> sub { $self->find_wanted },
		no_chdir	=> 0,
		}, "/" );

	#
	# Deletion Detection
	#

	my $filelist = $self->dbref->lookup_filelist( $self->group, $self->groupbase );

	foreach my $fileobj ( @{ $filelist } ){
		if( ! -e $fileobj->filepath ){
			$self->log->debug("File %s was deleted", $fileobj->filepath );
			$fileobj->last_transaction( $self->current_transaction_id );
			$self->dbref->mark_deleted( $fileobj);
		}
	}
} # end scan()

sub find_wanted {
	my( $self ) = @_;

	my $found_file = $File::Find::name;

	my $lookup_file = $self->dbref->lookup_file( $found_file, $self->group, $self->groupbase );

	if( ! defined $self->scan_count ){
		$self->scan_count(1);
	}

	$self->log->info("File Found: %s - %s", $self->scan_count, $found_file);

	$self->scan_count( $self->scan_count + 1 );

	my $found_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
	$found_file_obj->get_file( $found_file, $self->group, $self->groupbase );

	#
	# Ok at this point we've found a file
	# and if $lookup_file is 0 then we've
	# found a new file, we should process
	# it and add it to the database
	#
	if( $lookup_file eq "0" ){
		$found_file_obj->checksum_file();
		$found_file_obj->last_transaction( $self->current_transaction_id );

		$self->log->debug("Found File Object:");

		$self->dbref->add_file( $found_file_obj );
		return;
	}

	my $lookup_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref );
	$lookup_file_obj->from_hash( $lookup_file );


	$self->log->debug("Comparison status: %s", ( $lookup_file_obj == $found_file_obj ? 1 : 0 ));
	if( $lookup_file_obj == $found_file_obj ){
		$self->log->debug("*** Objects are identical");
		return;
	}

	#
	# At this point we know the files aren't identical, and we should update the database, that's thankfully fairly easy
	#

	# prep the object since it's obviously changed
	$found_file_obj->checksum_file();
	$found_file_obj->last_transaction( $self->current_transaction_id() );

	# update the file in the database
	$self->dbref->update_file( $found_file_obj );
} #end find_wanted()

sub create_transaction_id {
	my( $self ) = @_;

	my $transaction_id = sha256_hex( $self->group ."-". $self->groupbase ."-". hostname() ."-". $$ ."-". time() );

	my $retval = $self->dbref->new_transaction_id( $self->group, $transaction_id );

	$self->log->debug("create_transaction_id retval: %s", $retval);

	$self->current_transaction_id( $transaction_id );
	return;
} # end create_transaction_id()

__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
