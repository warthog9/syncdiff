#!/usr/bin/perl

package SyncDiff::Scanner 0.01;
use Moose;

extends qw(SyncDiff::Forkable);

# SyncDiff parts I need

use SyncDiff::File;
use SyncDiff::DB;
use SyncDiff::Util;

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

	print "About to chroot\n";

	chroot( $self->groupbase );
	chdir( "/" );

	print "chrooted\n";

	$self->scan();
}; # end run_child();

sub scan {
	my( $self ) = @_;

	print "I'm SCANNING I'm SCANNING! - $$\n";

	$self->create_transaction_id();

	find( {
		wanted		=> sub { $self->find_wanted },
		no_chdir	=> 0,
		}, "/" );
} # end scan()

sub find_wanted {
	my( $self ) = @_;

	my $found_file = $File::Find::name;

	my $lookup_file = $self->dbref->lookup_file( $found_file, $self->group, $self->groupbase );

	print "*** lookup file\n";
	print Dumper $lookup_file;
	print "^^^^^^^^^^^^^^^\n";

	if( ! defined $self->scan_count ){
		$self->scan_count(1);
	}

	print "File Found: ". $self->scan_count ." - ". $found_file ."\n";

	$self->scan_count( $self->scan_count + 1 );

	my $found_file_obj = SyncDiff::File->new(dbref => $self->dbref);
	$found_file_obj->get_file( $found_file, $self->group, $self->groupbase );

	print Dumper $found_file_obj;

	#
	# Ok at this point we've found a file
	# and if $lookup_file is 0 then we've
	# found a new file, we should process
	# it and add it to the database
	#
	if( $lookup_file eq "0" ){
		$found_file_obj->checksum_file();
		$found_file_obj->last_transaction( $self->current_transaction_id );

		print "Found File Object:\n";
		print Dumper $found_file_obj;

		$self->dbref->add_file( $found_file_obj );
		return;
	}

	my $lookup_file_obj = SyncDiff::File->new(dbref => $self->dbref );
	$lookup_file_obj->from_hash( $lookup_file );


	print "Comparison status: ". ( $lookup_file_obj == $found_file_obj ) ."\n";
	if( $lookup_file_obj == $found_file_obj ){
		print "*** Objects are identical\n";
		return;
	}

	#
	# At this point we know the files aren't identical, and we should update the database, that's thankfully fairly easy
	#

	# prep the object since it's obviously changed
	$found_file_obj->checksum();
	$found_file_obj->last_transaction( $self->current_transaction_id() );

	# update the file in the database
	$self->dbref->update_file( $found_file_obj );
} #end find_wanted()

sub create_transaction_id {
	my( $self ) = @_;

	my $transaction_id = sha256_hex( $self->group ."-". $self->groupbase ."-". hostname() ."-". $$ ."-". time() );

	
##	print "--------------------------\n";
##	print "SyncDiff::Scanner->create_transaction_id() - transaction_id:\n";
##	print "--------------------------\n";
##	print Dumper $transaction_id;
##	print "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

##	print "\t*** About to create new transaction id in database!!!!\n";

	my $retval = $self->dbref->new_transaction_id( $transaction_id );

	print "create_transaction_id retval: ". $retval ."\n";

##	print "\t*** Done creating new transaction id in database\n";

	$self->current_transaction_id( $transaction_id );
	return;
} # end create_transaction_id()

#no moose;
#__PACKAGE__->meta->make_immutable;
__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;