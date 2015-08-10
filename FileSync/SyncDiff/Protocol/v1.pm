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
use FileSync::SyncDiff::Log;

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

# Logger system
has 'log' => (
		is => 'rw',
		isa => 'FileSync::SyncDiff::Log',
		default => sub {
			return FileSync::SyncDiff::Log->new();
		}
);

sub setup {
	my( $self ) = @_;

	my %request = (
		request_version => $self->version
	);

	my $response = $self->send_request( %request );

	if( $response ne "1.0" ){  # This is the only protocol version we support right now
		$self->log->fatal("We don't currently support protocol version: %s - bailing out", $response);
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

	$self->log->debug("Client is now running with Protocol major version 1");

	my $remote_current_log_position = $self->getCurrentLogPosition();
	my $remote_previous_log_position = $dbref->get_remote_log_position( $self->hostname, $self->group );

	$self->log->debug("Current log position | %s |", $remote_current_log_position);
	$self->log->debug("Previous log position | %s |", $remote_previous_log_position);

	if( $remote_current_log_position ne $remote_previous_log_position ){
		$self->log->info("Updates were found!");

		my $file_updates = $self->get_updates_from_remote( $remote_previous_log_position);

		$self->log->debug("Files changed array: %s", Dumper $file_updates);
		$self->log->debug("^^^^^^^^^^^^^^^^^^^^");

		$self->log->debug("Going to save this out as: %s | %s | %s", $self->hostname, $self->group, $remote_current_log_position);
		$dbref->set_remote_log_position( $self->hostname, $self->group, $remote_current_log_position );
	} else {
		$self->log->info("No updates found");
	}
} # end client_run()

sub get_updates_from_remote {
	my( $self, $remote_previous_log_position ) = @_;
	
	my %request = (
		'v1_operation'	=>	'get_files_changed_since',
		'transactionid'	=>	$remote_previous_log_position,
	);

	my $response = $self->send_request( %request );

	$self->log->debug("Files Changed Since %s", $remote_previous_log_position);
	$self->log->debug(Dumper $response);

	my $x = 0;
	my $num_keys = keys %{$response};

	$self->log->debug("--------------------------------------------------------------");
	$self->log->debug("***                  STARTING FILE                         ***");
	$self->log->debug("***                  %3d/%3d                               ***", $x, $num_keys);
	$self->log->debug("--------------------------------------------------------------");
	$x = $x + 1;

	foreach my $id ( sort { $a <=> $b } keys %{$response} ){
		$self->log->debug("Id is: %s",$id);

		my $temp_file = FileSync::SyncDiff::File->new(dbref => $self->dbref );
		$temp_file->from_hash( $response->{$id} );	

		$self->log->debug("Before fork:");
		$self->log->debug(Dumper $temp_file);

		my $pid = 0;

		if( $temp_file->filetype ne "file" ){
			$self->log->debug("--------------------------------------------------------------");
			$self->log->debug("***                  NEXT FILE                             ***");
			$self->log->debug("***                  %3d/%3d                               ***", $x, $num_keys);
			$self->log->debug("--------------------------------------------------------------");
			$x = $x + 1;
			next;
		}

		if( ( $pid = fork() ) == 0 ){
			# child process
			$self->log->debug("V1: About to chroot to - | %s |", $self->groupbase);

			$self->log->debug("Group base: %s", $self->groupbase);

			chroot( $self->groupbase );
			chdir( "/" );

			$self->log->debug("chrooted");

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

		$self->log->debug("Going to wait for child:");
		do {
			$kid = waitpid($pid,0);
		} while $kid > 0;
		my $child_ret_code = $?;

		$self->log->debug("Pid we were expecting: %s | Pid that Died: %s", $pid, $kid);
		$self->log->debug("Child Return Code: |%s|",$child_ret_code);

		if( $temp_file->filetype eq "file" ){

			my $new_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
			$new_file_obj->get_file( $temp_file->filepath, $self->group, $self->groupbase );
			$new_file_obj->checksum_file();

			$self->log->debug($new_file_obj);

			$self->log->debug("External checking of checksum:");
			$self->log->debug("Passed checksum: %s", $temp_file->checksum());
			$self->log->debug("Saved checksum: %s", $new_file_obj->checksum());
			if( $new_file_obj->checksum() ne $temp_file->checksum ){
				$self->log->fatal("Checksums don't match - ERGH!");
			}
			#exit();
		}
		$self->log->debug("--------------------------------------------------------------");
		$self->log->debug("***                  NEXT FILE                             ***");
		$self->log->debug("***                  %3d/%3d                               ***", $x, $num_keys);
		$self->log->debug("--------------------------------------------------------------");
		$x = $x + 1;
	} #end foreach response I.E. files

} # end get_updates_from_remote()

sub sync_file {
	my( $self, $path, $filename, $filepath, $checksum) = @_;

	my $sig_buffer = undef;
	my $basis = undef;
	my $sig = undef;

	$self->log->debug("Going to sync the file %s", $filepath);

	if( ! -d $path ){
		# path hasn't been created yet
		# we should process the dirs first
		# but for now I'm just going to
		# do a mkdir based on the 
		# path for the file

		$self->log->debug("Making directory: %s", $path);
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
		$self->log->error("*******************************************");
		$self->log->error("This isn't the response we are expecting...");
		$self->log->error("*******************************************");
		$self->log->error(Dumper $response_hash);
		$self->log->error( "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^");
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

		$self->log->debug("EXTRA: %s", $line);
	}

	$self->log->debug(Dumper $response_hash);

	my $checksum_resp = sha256_base64($response_hash->{delta});
	$self->log->debug("v1 - response_hash calculated: %s", $checksum_resp);
	$self->log->debug("v1 - reponse_hash what sent:   %s", $response_hash->{checksum});
	if( $checksum_resp ne $response_hash->{checksum}){
		$self->log->error("Ok on the recieve buffer the checksums don't match WTF!");
		sleep 30;
	}
	
	my $response64 = $response_hash->{delta};
	
	my $response = decode_base64( $response64 );
	
	$self->log->debug("----------------------");
	$self->log->debug("Response:");
	$self->log->debug("----------------------");

	$self->log->debug("Length: %s", length( $response64 ));
	$self->log->debug("Response: | %s |", $response64);
	$self->log->debug("^^^^^^^^^^^^^^^^^^^^^^");

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

	$self->log->debug("Delta filename: %s", $delta_filename);

	($new, $new_path) = tempfile( UNLINK => 1, );
	binmode( $new, ':raw');

	$self->log->info("Chocking around here I bet");
	File::Rdiff::patch_file $base, $delta, $new;
	$self->log->info("Yup");

	close $new;
	close $base;
	close $delta;

	my $new_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
	$new_file_obj->get_file( $new_path, $self->group, $self->groupbase );
	$new_file_obj->checksum_file();

	$self->log->debug("Transfered file checksum: %s", $checksum);

	$self->log->debug("New File Checksum:        %s", $new_file_obj->checksum());

	if( $checksum ne $new_file_obj->checksum() ){
		$self->log->error("*************** Checksums don't match");
		return;
	}

	move( $new_path, $filepath );

} # end sync_file

sub _get_files_changed_since {
	my( $self, $transactionid ) = @_;
	my $dbref = $self->dbref;
	
	my $file_list = $dbref->get_files_changed_since( $self->group, $transactionid );

	$self->log->debug("V1: Files found changed since %s", $transactionid);
	$self->log->debug(Dumper $file_list);

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
		$self->log->debug("--------------------------------------------------------------");
		$self->log->debug("***                  START SYNCFILE                        ***");
		$self->log->debug("--------------------------------------------------------------");

		my $pid = 0;

		if( ( $pid = fork() ) == 0 ){
			# child process
			chroot( $self->groupbase );
			chdir( "/" );

			$self->log->debug("chrooted");

			my $sync_ret = $self->_syncfile(
				$response->{path},
				$response->{filename},
				$response->{filepath},
				$response->{signature},
			);

			$self->log->debug("~~ after syncfile response length: %s", length( $sync_ret ));
			$self->log->debug("Length of encoded delta buffer: %s", length( $sync_ret->{delta} ));

			$self->plain_send( $sync_ret );
			exit(0);
		}

		my $child;
		do {
			$child = waitpid( $pid, 0);
		} while( $child > 0);
		$self->log->debug("--------------------------------------------------------------");
		$self->log->debug("***                  END SYNCFILE                          ***");
		$self->log->debug("--------------------------------------------------------------");
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

	$self->log->debug(Dumper $sig);

	$self->log->info("Loading sig from %s file", $filename);

	$sig = loadsig_file $sig;

	ref $sig or exit 1;

	$self->log->info("Building hash table");

	$sig->build_hash_table;

	$self->log->info("Deltafying things");

	File::Rdiff::delta_file $sig, $new, $delta;

	my $delta_buffer = "";

	seek $delta, 0, 0;
	my $bytes_read = 0;
	my $data;
	while ((my $n = read $delta, $data, 4096) != 0) {
		$bytes_read = $bytes_read + $n;
		$delta_buffer .= $data;
	}
	$self->log->debug("~ %s from Delta file",$bytes_read);

	$self->log->debug("Length of Delta Buffer: %s", length( $delta_buffer ));

	unlink $sig_filename;
	close $delta;
	unlink $delta_filename;
	close $new;

	my $delta_buffer_encoded = encode_base64( $delta_buffer );
	$self->log->debug("Length of Delta Buffer: %s", length( $delta_buffer ));
	$self->log->debug("Length of encoded delta buffer: %s", length( $delta_buffer_encoded ));



	$self->log->debug("--------------------------");
	$self->log->debug("Delta Buffer encoded:");
	$self->log->debug("--------------------------");
	$self->log->debug("Total length: %s", length( $delta_buffer_encoded ));
	$self->log->debug("^^^^^^^^^^^^^^^^^^^^^^^^^^");

	my %response = (
		delta	=>	$delta_buffer_encoded,
		checksum =>	sha256_base64( $delta_buffer_encoded),
		checksum_pre => sha256_base64( $delta_buffer ),
		path =>	$path,
		filename => $filename,
		filepath => $filepath,
	);

	$self->log->debug("Length of encoded delta buffer: %s", length( $response{delta} ));

	return \%response;
}

__PACKAGE__->meta->make_immutable;

1;
