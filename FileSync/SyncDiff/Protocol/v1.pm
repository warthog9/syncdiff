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

#	print "Protocol V1 - Setup - Version request response:\n";
#	print Dumper $response;

	if( $response ne "1.0" ){  # This is the only protocol version we support right now
		print "We don't currently support protocol version: ". $response ." - bailing out\n";
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

	print "Client is now running with Protocol major version 1\n";

	my $remote_current_log_position = $self->getCurrentLogPosition();
	my $remote_previous_log_position = $dbref->get_remote_log_position( $self->hostname, $self->group );

	print "Current log position |". $remote_current_log_position ."|\n";
	print "Previous log position |". $remote_previous_log_position ."|\n";

	if( $remote_current_log_position ne $remote_previous_log_position ){
		print "Updates were found!\n";

		my $file_updates = $self->get_updates_from_remote( $remote_previous_log_position);

		print "Files changed array:\n";
		print Dumper $file_updates;
		print "^^^^^^^^^^^^^^^^^^^^\n";

		print "Going to save this out as: ". $self->hostname ." | ". $self->group ." | ". $remote_current_log_position ."\n";
		$dbref->set_remote_log_position( $self->hostname, $self->group, $remote_current_log_position );
	} else {
		print "No updates found\n";
	}
} # end client_run()

# save a reference on a using shared memory
my $ref_shared_memory;

sub _lock {
    my ($self) = @_;
    my $share = IPC::ShareLite->new(
        -key     => 'sync',
        -create  => 'yes',
        -destroy => 'no'
    ) || confess $!;

    $ref_shared_memory = $share;

    my $lock_client = 1;

    return $share->store( $lock_client );
}

sub _unlock {
    my ($self) = @_;
    my $share;
    eval {
        $share = IPC::ShareLite->new(
            -key     => 'sync',
            -create  => 'no',
            -destroy => 'no'
        );
    } || return;

    my $lock_client = 0;

    return $share->store( $lock_client );
}

sub _is_lock {
    my ($self) = @_;
    my $share;
    eval {
        $share = IPC::ShareLite->new(
            -key     => 'sync',
            -create  => 'no',
            -destroy => 'no'
        );
    } || return;

    return $share->fetch();
}

sub get_updates_from_remote {
	my( $self, $remote_previous_log_position ) = @_;
	
	my %request = (
		'v1_operation'	=>	'get_files_changed_since',
		'transactionid'	=>	$remote_previous_log_position,
	);

	my $response = $self->send_request( %request );

	print "Files Changed Since $remote_previous_log_position:\n";
	print Dumper $response;

	my $x = 0;
	my $num_keys = keys %{$response};

	print "--------------------------------------------------------------\n";
	print "***                  STARTING FILE                         ***\n";
	printf("***                  %3d/%3d                               ***\n", $x, $num_keys);
	print "--------------------------------------------------------------\n";
	$x = $x + 1;

	foreach my $id ( sort { $a <=> $b } keys %{$response} ){
		print "Id is: $id\n";

		my $temp_file = FileSync::SyncDiff::File->new(dbref => $self->dbref );
		$temp_file->from_hash( $response->{$id} );	

		print "Before fork:\n";
		print Dumper $temp_file;

		my $pid = 0;

		if( $temp_file->filetype ne "file" ){
			print "--------------------------------------------------------------\n";
			print "***                  NEXT FILE                             ***\n";
			printf("***                  %3d/%3d                               ***\n", $x, $num_keys);
			print "--------------------------------------------------------------\n";
			$x = $x + 1;
			next;
		}

		if( ( $pid = fork() ) == 0 ){
			# child process
			print "V1: About to chroot to - |". $self->groupbase ."|\n";

			print "Group base: ". $self->groupbase ."\n";

			chroot( $self->groupbase );
			chdir( "/" );

			print "chrooted\n";

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

			#if( -e $temp_file->filepath ){
				#file exists, we should compare things before we get too far here.... *BUT* I don't want to deal with that code quite yet
			#}
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

		print "Going to wait for child:\n";
		do {
			$kid = waitpid($pid,0);
			print ".";
		} while $kid > 0;
		my $child_ret_code = $?;
		print "\n";
		print "Pid we were expecting: $pid | Pid that Died: $kid\n";
		print "Child Return Code: |$child_ret_code|\n";

		if( $temp_file->filetype eq "file" ){

			my $new_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
			$new_file_obj->get_file( $temp_file->filepath, $self->group, $self->groupbase );
			$new_file_obj->checksum_file();

			print Dumper $new_file_obj;

			print "External checking of checksum: \n";
			print "Passed checksum: ". $temp_file->checksum() ."\n";
			print "Saved checksum:  ". $new_file_obj->checksum() ."\n";
			if( $new_file_obj->checksum() ne $temp_file->checksum ){
				print "Checksums don't match - ERGH!\n";
				exit();
			}
			#exit();
		}
		print "--------------------------------------------------------------\n";
		print "***                  NEXT FILE                             ***\n";
		printf("***                  %3d/%3d                               ***\n", $x, $num_keys);
		print "--------------------------------------------------------------\n";
		$x = $x + 1;
	} #end foreach response I.E. files

} # end get_updates_from_remote()

sub sync_file {
	my( $self, $path, $filename, $filepath, $checksum) = @_;

	my $sig_buffer = undef;
	my $basis = undef;
	my $sig = undef;

	print "Going to sync the file $filepath\n";

	if( ! -d $path ){
		# path hasn't been created yet
		# we should process the dirs first
		# but for now I'm just going to
		# do a mkdir based on the 
		# path for the file

		print "Making directory: ". $path ."\n";
		make_path($path, { verbose => 1, } );
	}

	my $dir = "/";
	#my $dir = "/group2/Kickstarter Deluxe Digital Album/";

#	opendir(DIR, $dir) or die $!;
#
#	while (my $file = readdir(DIR)) {
#		print "$file\n";
#	}
#
#	closedir(DIR);

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

	#print "----------------------\n";
	#print "Request:\n";
	#print "----------------------\n";
	#print Dumper \%request;
	#print "^^^^^^^^^^^^^^^^^^^^^^\n";

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
		print "*******************************************\n";
		print "This isn't the response we are expecting...\n";
		print "*******************************************\n";
		print Dumper $response_hash;
		print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";
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

		print "EXTRA: $line\n";
	}

	print Dumper $response_hash;

	my $checksum_resp = sha256_base64($response_hash->{delta});
	print "v1 - response_hash calculated: ". $checksum_resp ."\n";
	print "v1 - reponse_hash what sent:   ". $response_hash->{checksum} ."\n";
	if( $checksum_resp ne $response_hash->{checksum}){
		print "Ok on the recieve buffer the checksums don't match WTF!\n";
		sleep 30;
	}
	
	my $response64 = $response_hash->{delta};
	
	my $response = decode_base64( $response64 );
	
	print "----------------------\n";
	print "Response:\n";
	print "----------------------\n";
	#print Dumper $response;
	#print Dumper $response64;
	print "Length: ". length( $response64 ) ."\n";
	print "Response: |". $response64 ."|\n";
	print "^^^^^^^^^^^^^^^^^^^^^^\n";

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

	print "Delta filename: $delta_filename\n";

#	my $new_path = $filepath;
#	print "New Path: ". $new_path ."$$\n";
	#open( $new, ">", $new_path .".new" ) or die "STUFF!: $!";
	#open( $new, ">", $new_path ) or die "STUFF!: $!";

	($new, $new_path) = tempfile( UNLINK => 1, );
	binmode( $new, ':raw');

	print "Chocking around here I bet\n";
	File::Rdiff::patch_file $base, $delta, $new;
	print "Yup\n";

	close $new;
	close $base;
	close $delta;
	#unlink $delta_filename;

	my $new_file_obj = FileSync::SyncDiff::File->new(dbref => $self->dbref);
	$new_file_obj->get_file( $new_path, $self->group, $self->groupbase );
	$new_file_obj->checksum_file();

	

	print "Transfered file checksum: ". $checksum ."\n";

	print "New File Checksum:        ". $new_file_obj->checksum() ."\n";

	if( $checksum ne $new_file_obj->checksum() ){
		print "*************** Checksums don't match\n";
		return;
	}

	move( $new_path, $filepath );

} # end sync_file

sub _get_files_changed_since {
	my( $self, $transactionid ) = @_;
	my $dbref = $self->dbref;
	
	my $file_list = $dbref->get_files_changed_since( $self->group, $transactionid );

	print "V1: Files found changed since $transactionid\n";
	print Dumper $file_list;

	return $file_list
} # end get_files_changed_since()

sub getCurrentLogPosition {
	my( $self ) = @_;

	my %request = (
		'v1_operation'	=>	'getLogPosition'
	);

	my $response = $self->send_request( %request );

#	print "Found Log Position response\n";
#	print Dumper $response;

	return $response;
} # end getCurrentLogPosition()

sub shareCurrentLogPosition {
	my( $self ) = @_;

	my $logPosition = $self->dbref->current_log_position();

#	print "Log position is:\n";
#	print Dumper $logPosition

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

#	print "Server version 1 got response: \n";
#	print Dumper $response;

	if( ! exists( $response->{v1_operation} ) ){
		return;
	}

	if( $response->{v1_operation} eq "getLogPosition" ){
#		print "DBref:\n";
#		print Dumper $self->dbref;
		my $logPosition = $self->dbref->current_log_position();
#		print "Found log position on Server:\n";
#		print Dumper $logPosition;
		return $logPosition;
	}
	if( $response->{v1_operation} eq "get_files_changed_since" ){
		my $files_changed_response = $self->_get_files_changed_since( $response->{transactionid} );
#		print "---------------------\n";
#		print "Response from get_files_changed_since:\n";
#		print "---------------------\n";
#		print Dumper $files_changed_response;
#		print "^^^^^^^^^^^^^^^^^^^^^\n";

		return $files_changed_response;
	}
	if( $response->{v1_operation} eq "syncfile" ){
		print "--------------------------------------------------------------\n";
		print "***                  START SYNCFILE                        ***\n";
		print "--------------------------------------------------------------\n";

		my $pid = 0;

		if( ( $pid = fork() ) == 0 ){
			# child process
			
			chroot( $self->groupbase );
			chdir( "/" );

			print "\n\n";
			print "chrooted\n";
			print "\n\n";

			
			my $sync_ret = $self->_syncfile(
				$response->{path},
				$response->{filename},
				$response->{filepath},
				$response->{signature},
			);

			print "~~ after syncfile response length: ". length( $sync_ret ) ."\n";
			print "Length of encoded delta buffer: ". length( $sync_ret->{delta} ) ."\n";

			$self->plain_send( $sync_ret );
			exit(0);
		}

		my $child;
		do {
			$child = waitpid( $pid, 0);
		} while( $child > 0);
		print "--------------------------------------------------------------\n";
		print "***                  END SYNCFILE                          ***\n";
		print "--------------------------------------------------------------\n";
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

#	print "--------------------------\n";
#	print "Sig64 encoded:\n";
#	print "--------------------------\n";
#	#my $str = $signature64;
#	#substr($str, 20) = "";
#	#print "$str\n";   # prints "abc"
#	print Dumper $signature64;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";


	my ($sig, $sig_filename) = tempfile();
	binmode( $sig, ":raw" );
	print $sig decode_base64( $signature64 );;
	seek $sig, 0, 0;

	print Dumper $sig;

	print "Loading sig file\n";

	$sig = loadsig_file $sig;

	ref $sig or exit 1;

	print "Building hash table\n";

	$sig->build_hash_table;

	print "Deltafying things\n";

	File::Rdiff::delta_file $sig, $new, $delta;

#	print "--------------------------\n";
#	print "Sig:\n";
#	print "--------------------------\n";
#	print Dumper $sig;
#	print "--------------------------\n";
#	print "New:\n";
#	print "--------------------------\n";
#	print Dumper $new;
#	print "--------------------------\n";
#	print "Delta:\n";
#	print "--------------------------\n";
#	print Dumper $delta;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my $delta_buffer = "";

	seek $delta, 0, 0;
	my $bytes_read = 0;
	my $data;
	while ((my $n = read $delta, $data, 4096) != 0) {
		#print "~~ $n bytes read\n";
		$bytes_read = $bytes_read + $n;
		$delta_buffer .= $data;
	}
	print "~ $bytes_read from Delta file\n";

	print "Length of Delta Buffer: ". length( $delta_buffer ) ."\n";


	#close $sig;
	unlink $sig_filename;
	close $delta;
	unlink $delta_filename;
	close $new;

	my $delta_buffer_encoded = encode_base64( $delta_buffer );
	print "Length of Delta Buffer: ". length( $delta_buffer ) ."\n";
	print "Length of encoded delta buffer: ". length( $delta_buffer_encoded ) ."\n";



	print "--------------------------\n";
	print "Delta Buffer encoded:\n";
	print "--------------------------\n";
#	my $str = $delta_buffer_encoded;
#	substr($str, 20) = "";
#	print "$str\n";   # prints "abc"
	#print Dumper $delta_buffer_encoded;
	print "Total length: ". length( $delta_buffer_encoded ). "\n";
	print "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

#	print "--------------------------\n";
#	print "Delta encoded:\n";
#	print "--------------------------\n";
#	my $str = $delta_buffer_encoded;
#	substr($str, 250) = "";
#	print "$str\n";   # prints "abc"
#	print substr( $str, 0, 250 ) ."\n";
#	print Dumper $delta_buffer_encoded;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^\n";



	my %response = (
		delta	=>	$delta_buffer_encoded,
		checksum =>	sha256_base64( $delta_buffer_encoded),
		checksum_pre => sha256_base64( $delta_buffer ),
		path =>	$path,
		filename => $filename,
		filepath => $filepath,
	);

	print "Length of encoded delta buffer: ". length( $response{delta} ) ."\n";

	#return $delta_buffer_encoded;
	return \%response;
}

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
