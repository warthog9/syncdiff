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

package FileSync::SyncDiff::Protocol::v1;
$FileSync::SyncDiff::Protocol::v1::VERSION = '0.01';
use Moose;

extends qw(FileSync::SyncDiff::SenderReceiver);

# SyncDiff parts I need

use FileSync::SyncDiff::File;

#
# Other Includes
#

use JSON::XS;
use File::Rdiff qw(:trace :nonblocking :file);
use MIME::Base64;
use File::Path qw(make_path remove_tree);
use PerlIO::scalar;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;
use Digest::SHA qw(sha256 sha256_hex sha256_base64);

#
# Debugging
#

use Data::Dumper;

#
# Getting on with it
#

has 'socket' => (
		is	=> 'rw',
		isa	=> 'IO::Socket::INET',
		required => 1,
		);

has 'version' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'hostname' => (
		is	=> 'rw',
		isa	=> 'Str',
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
		required => 0,
		);

has '+short_rev' => (
		default	=> 'no',
		);
	

sub setup {
	my( $self ) = @_;

	my %request = (
		request_version => $self->version
	);

	my $response = $self->send_request( %request );

	if( $response ne "1.0" ){  # This is the only protocol version we support right now
		print STDERR "We don't currently support protocol version: ". $response ." - bailing out\n";
		exit(1);
	}
} # end setup()

#
# This is the main routine, once the protocol version
# has been figured out there's no point in the parent
# trying to tell all the children how to work, so 
# it will call into run() and basically let things
# go from there.  It's then up to the protocol to 
# negotiate with itself on how the rest of the interaction
# works.  Why?  So that future protocols can be
# completely different, who knows maybe someone
# will build a p2p backend that's more BitTorrent
# like that doesn't suck.
#

sub client_run {
	my( $self ) = @_;
	my $dbref = $self->dbref;

	print STDERR "Client is now running with Protocol major version 1\n";

	my $remote_current_log_position = $self->getCurrentLogPosition();
	my $remote_previous_log_position = $dbref->get_remote_log_position( $self->hostname, $self->group );

	print STDERR "Current log position |". $remote_current_log_position ."|\n";
	print STDERR "Previous log position |". $remote_previous_log_position ."|\n";

	if( $remote_current_log_position ne $remote_previous_log_position ){
		print STDERR "Updates were found!\n";

		my $file_updates = $self->get_updates_from_remote( $remote_previous_log_position);

		print STDERR "Files changed array:\n";
		print STDERR Dumper $file_updates;
		print STDERR "^^^^^^^^^^^^^^^^^^^^\n";

		print STDERR "Going to save this out as: ". $self->hostname ." | ". $self->group ." | ". $remote_current_log_position ."\n";
		$dbref->set_remote_log_position( $self->hostname, $self->group, $remote_current_log_position );
	} else {
		print STDERR "No updates found\n";
	}
} # end client_run()

sub get_updates_from_remote {
	my( $self, $remote_previous_log_position ) = @_;
	
	my %request = (
		'v1_operation'	=>	'get_files_changed_since',
		'transactionid'	=>	$remote_previous_log_position,
	);

	my $response = $self->send_request( %request );

	print STDERR "Files Changed Since $remote_previous_log_position:\n";
	print STDERR Dumper $response;

	my $x = 0;
	my $num_keys = keys %{$response};

	print STDERR "--------------------------------------------------------------\n";
	print STDERR "***                  STARTING FILE                         ***\n";
	printf(STDERR "***                  %3d/%3d                               ***\n", $x, $num_keys);
	print STDERR "--------------------------------------------------------------\n";
	$x = $x + 1;

	foreach my $id ( sort { $a <=> $b } keys %{$response} ){
		print STDERR "Id is: $id\n";

		my $temp_file = FileSync::SyncDiff::File->new(dbref => $self->dbref );
		$temp_file->from_hash( $response->{$id} );	

		print STDERR "Before fork:\n";
		print STDERR Dumper $temp_file;

		my $pid = 0;

		if( $temp_file->filetype ne "file" ){
			print STDERR "--------------------------------------------------------------\n";
			print STDERR "***                  NEXT FILE                             ***\n";
			printf(STDERR "***                  %3d/%3d                               ***\n", $x, $num_keys);
			print STDERR "--------------------------------------------------------------\n";
			$x = $x + 1;
			next;
		}

		if( ( $pid = fork() ) == 0 ){
			# child process
			print STDERR "V1: About to chroot to - |". $self->groupbase ."|\n";

			print STDERR "Group base: ". $self->groupbase ."\n";

			chroot( $self->groupbase );
			chdir( "/" );

			print STDERR "chrooted\n";

			# Ok for simplicities sake, and to
			# get past the file transfer section
			# I'm going to assume that every
			# file that's changed in the list
			# just needs to be synced over.
			#
			# Is this efficient: no
			# Is it simple: yes
			# Does it mean I get some file
			# transfers going: YES
			#
			# The rest of this complexity can
			# be added later, and then can 
			# happily (from a marketing perspective)
			# be used as "We made it X% faster!"
			# or "NOW WITH MORE SPEED!" (ok
			# that last one might not be
			# good marketing material on second
			# thought....

			if( $temp_file->filetype eq "file" ){
				$self->sync_file( $temp_file->path, $temp_file->filename, $temp_file->filepath, $temp_file->checksum );
			}

			exit(0);
		}
		
		# parent process
		#	Wait for the child file transfer
		#	to complete.  The child is 
		#	chrooted to the syncbase.  The 
		#	syncbase might need to get
		#	worked on so that it's read
		#	from the config file vs. 
		#	something else.  *OR* 
		#	more likely for now, I'm going
		#	to ignore the remote syncbase
		#	and use the one in the config
		#	file.  This means we only support
		#	one syncbase per config, which
		#	might be ok, and obviously easier
		#	from the code perspective
		my $kid = undef;

		print STDERR "Going to wait for child:\n";
		do {
			$kid = waitpid($pid,0);
			print STDERR ".";
		} while $kid > 0;
		my $child_ret_code = $?;
		print STDERR "\n";
		print STDERR "Pid we were expecting: $pid | Pid that Died: $kid\n";
		print STDERR "Child Return Code: |$child_ret_code|\n";

		if( $temp_file->filetype eq "file" ){

			my $new_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
			$new_file_obj->get_file( $temp_file->filepath, $self->group, $self->groupbase );
			$new_file_obj->checksum_file();

			print STDERR Dumper $new_file_obj;

			print STDERR "External checking of checksum: \n";
			print STDERR "Passed checksum: ". $temp_file->checksum() ."\n";
			print STDERR "Saved checksum:  ". $new_file_obj->checksum() ."\n";
			if( $new_file_obj->checksum() ne $temp_file->checksum ){
				print STDERR "Checksums don't match - ERGH!\n";
				exit();
			}
			#exit();
		}
		print STDERR "--------------------------------------------------------------\n";
		print STDERR "***                  NEXT FILE                             ***\n";
		printf(STDERR "***                  %3d/%3d                               ***\n", $x, $num_keys);
		print STDERR "--------------------------------------------------------------\n";
		$x = $x + 1;
	} #end foreach response I.E. files

} # end get_updates_from_remote()

sub sync_file {
	my( $self, $path, $filename, $filepath, $checksum) = @_;

	my $sig_buffer = undef;
	my $basis = undef;
	my $sig = undef;

	print STDERR "Going to sync the file $filepath\n";

	if( ! -d $path ){
		# path hasn't been created yet
		# we should process the dirs first
		# but for now I'm just going to
		# do a mkdir based on the 
		# path for the file

		print STDERR "Making directory: ". $path ."\n";
		make_path($path, { verbose => 1, } );
	}

	my $dir = "/";

	if( ! -e $filepath ){
		open HANDLE, ">>$filepath" or die "touch $filepath: $!\n"; 
		close HANDLE;
	}

	open $basis, "<", $filepath or die "$filepath - $!";
	open $sig, ">", \$sig_buffer or die "sig_buffer: $!";

	my $job = new_sig File::Rdiff::Job 128;
	my $buf = new File::Rdiff::Buffers 4096;

	while ($job->iter($buf) == BLOCKED) {
		# fetch more input data
		$buf->avail_in or do {
			my $in;
			65536 == sysread $basis, $in, 65536 or $buf->eof;
			$buf->in($in);
		};
		print $sig $buf->out;
	}
	print $sig $buf->out;

	close $sig;
	close $basis;

	my %request = (
		'v1_operation'	=>	'syncfile',
		'signature'	=>	encode_base64($sig_buffer),
		'filename'	=>	$filename,
		'filepath'	=>	$filepath,
		'path'		=>	$path,
	);

	my $response_hash = $self->send_request( %request );

	while(
		! defined $response_hash->{filename}
		||
		! defined $response_hash->{path}
		||
		$response_hash->{filename} ne $filename
		||
		$response_hash->{path} ne $path
	){
		print STDERR "*******************************************\n";
		print STDERR "This isn't the response we are expecting...\n";
		print STDERR "*******************************************\n";
		print STDERR Dumper $response_hash;
		print STDERR "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";
		$response_hash = $self->plain_receiver( \%request );
	}


	# response is acquired, lets actually lay some bits down
	if( $response_hash->{filename} ne $filename ){
		my $line = undef;
		my $socket = $self->socket;

		while( $line = <$socket> ){
			if( defined $line  ){
				chomp( $line );
				last if( $line ne "" );
			}
		} # end while loop waiting on socket to return

		print STDERR "EXTRA: $line\n";
	}

	print STDERR Dumper $response_hash;

	my $checksum_resp = sha256_base64($response_hash->{delta});
	print STDERR "v1 - response_hash calculated: ". $checksum_resp ."\n";
	print STDERR "v1 - reponse_hash what sent:   ". $response_hash->{checksum} ."\n";
	if( $checksum_resp ne $response_hash->{checksum}){
		print STDERR "Ok on the recieve buffer the checksums don't match WTF!\n";
		sleep 30;
	}
	
	my $response64 = $response_hash->{delta};
	
	my $response = decode_base64( $response64 );
	
	print STDERR "----------------------\n";
	print STDERR "Response:\n";
	print STDERR "----------------------\n";

	print STDERR "Length: ". length( $response64 ) ."\n";
	print STDERR "Response: |". $response64 ."|\n";
	print STDERR "^^^^^^^^^^^^^^^^^^^^^^\n";

	my $base = undef;

	my $delta = undef;
	my $delta_filename = undef;

	my $new = undef;
	my $new_path = undef;
	my $new_filename = undef;

	open $base,  "<". $filepath or die "$filepath: $!";

	($delta, $delta_filename) = tempfile( UNLINK => 1 );
	binmode( $delta, ':raw');
	print $delta $response;
	seek $delta, 0, 0;

	print STDERR "Delta filename: $delta_filename\n";

	($new, $new_path) = tempfile( UNLINK => 1, );
	binmode( $new, ':raw');

	print STDERR "Chocking around here I bet\n";
	File::Rdiff::patch_file $base, $delta, $new;
	print STDERR "Yup\n";

	close $new;
	close $base;
	close $delta;

	my $new_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
	$new_file_obj->get_file( $new_path, $self->group, $self->groupbase );
	$new_file_obj->checksum_file();

	print STDERR "Transfered file checksum: ". $checksum ."\n";

	print STDERR "New File Checksum:        ". $new_file_obj->checksum() ."\n";

	if( $checksum ne $new_file_obj->checksum() ){
		print STDERR "*************** Checksums don't match\n";
		return;
	}

	move( $new_path, $filepath );

} # end sync_file

sub _get_files_changed_since {
	my( $self, $transactionid ) = @_;
	my $dbref = $self->dbref;
	
	my $file_list = $dbref->get_files_changed_since( $self->group, $transactionid );

	print STDERR "V1: Files found changed since $transactionid\n";
	print STDERR Dumper $file_list;

	return $file_list
} # end get_files_changed_since()

sub getCurrentLogPosition {
	my( $self ) = @_;

	my %request = (
		'v1_operation'	=>	'getLogPosition'
	);

	my $response = $self->send_request( %request );

	return $response;
} # end getCurrentLogPosition()

sub shareCurrentLogPosition {
	my( $self ) = @_;

	my $logPosition = $self->dbref->current_log_position();

} # end shareCurrentLogPosition()
	
sub getVersion {
	my( $self ) = @_;
	
	return "1.0"
} # end getVersion()

#
# This is the main routine for the server side of things
# shouldn't be *TOO* dissimilar to the client, but yeah
#

sub server_process_request {
	my( $self, $response ) = @_;

	if( ! exists( $response->{v1_operation} ) ){
		return;
	}

	if( $response->{v1_operation} eq "getLogPosition" ){
		my $logPosition = $self->dbref->current_log_position();
		return $logPosition;
	}
	if( $response->{v1_operation} eq "get_files_changed_since" ){
		my $files_changed_response = $self->_get_files_changed_since( $response->{transactionid} );
		return $files_changed_response;
	}
	if( $response->{v1_operation} eq "syncfile" ){
		print STDERR "--------------------------------------------------------------\n";
		print STDERR "***                  START SYNCFILE                        ***\n";
		print STDERR "--------------------------------------------------------------\n";

		my $pid = 0;

		if( ( $pid = fork() ) == 0 ){
			# child process
			chroot( $self->groupbase );
			chdir( "/" );

			print STDERR "\n\n";
			print STDERR "chrooted\n";
			print STDERR "\n\n";

			my $sync_ret = $self->_syncfile(
				$response->{path},
				$response->{filename},
				$response->{filepath},
				$response->{signature},
			);

			print STDERR "~~ after syncfile response length: ". length( $sync_ret ) ."\n";
			print STDERR "Length of encoded delta buffer: ". length( $sync_ret->{delta} ) ."\n";

			$self->plain_send( $sync_ret );
			exit(0);
		}

		my $child;
		do {
			$child = waitpid( $pid, 0);
		} while( $child > 0);
		print STDERR "--------------------------------------------------------------\n";
		print STDERR "***                  END SYNCFILE                          ***\n";
		print STDERR "--------------------------------------------------------------\n";
	}

	return undef;
} # end server_progress_request()

sub _syncfile {
	my( $self, $path, $filename, $filepath, $signature64 ) = @_;

	# We need to build the delta, based on the signature

	my ($delta, $delta_filename) = tempfile();
	binmode( $delta, ':raw');

	my $new;
	open( $new, "<", $filepath ) or die "new_buffer: $filepath - $!\n";	
	binmode( $new, ':raw');

	my ($sig, $sig_filename) = tempfile();
	binmode( $sig, ":raw" );
	print $sig decode_base64( $signature64 );;
	seek $sig, 0, 0;

	print STDERR Dumper $sig;

	print STDERR "Loading sig file\n";

	$sig = loadsig_file $sig;

	ref $sig or exit 1;

	print STDERR "Building hash table\n";

	$sig->build_hash_table;

	print STDERR "Deltafying things\n";

	File::Rdiff::delta_file $sig, $new, $delta;

	my $delta_buffer = "";

	seek $delta, 0, 0;
	my $bytes_read = 0;
	my $data;
	while ((my $n = read $delta, $data, 4096) != 0) {
		$bytes_read = $bytes_read + $n;
		$delta_buffer .= $data;
	}
	print STDERR "~ $bytes_read from Delta file\n";

	print STDERR "Length of Delta Buffer: ". length( $delta_buffer ) ."\n";

	unlink $sig_filename;
	close $delta;
	unlink $delta_filename;
	close $new;

	my $delta_buffer_encoded = encode_base64( $delta_buffer );
	print STDERR "Length of Delta Buffer: ". length( $delta_buffer ) ."\n";
	print STDERR "Length of encoded delta buffer: ". length( $delta_buffer_encoded ) ."\n";



	print STDERR "--------------------------\n";
	print STDERR "Delta Buffer encoded:\n";
	print STDERR "--------------------------\n";
	print STDERR "Total length: ". length( $delta_buffer_encoded ). "\n";
	print STDERR "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my %response = (
		delta	=>	$delta_buffer_encoded,
		checksum =>	sha256_base64( $delta_buffer_encoded),
		checksum_pre => sha256_base64( $delta_buffer ),
		path =>	$path,
		filename => $filename,
		filepath => $filepath,
	);

	print STDERR "Length of encoded delta buffer: ". length( $response{delta} ) ."\n";

	return \%response;
}

__PACKAGE__->meta->make_immutable;

1;
