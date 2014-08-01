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

package FileSync::SyncDiff::DB;
$FileSync::SyncDiff::DB::VERSION = '0.01';
use Moose;

extends qw(FileSync::SyncDiff::Forkable);

#
# Needed to communicate with other modules
#

use FileSync::SyncDiff::File;
use FileSync::SyncDiff::Util;
use FileSync::SyncDiff::Config;

#
# Needed for dealing with DB stuff
#

use DBD::SQLite;
use IO::Socket;
use JSON::XS;
use MIME::Base64;
use Sys::Hostname;
use Digest::SHA qw(sha256_hex);

#
# Debugging
#

use Data::Dumper;

# End includes

#
# moose variables
#

has 'file' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'dbh' => (
		is	=> 'ro',
		isa	=> 'DBI::db',
		writer	=> '_write_dbh',
		);

has 'config' => (
		is	=> 'rw',
		isa	=> 'FileSync::SyncDiff::Config',
		required => 1,
		);

# End variables

sub connect_and_fork {
	my( $self, $file_to_open ) = @_;

	$self->connect( $file_to_open );
	$self->fork();
} # end connect_and_fork()

sub connect {
	my( $self, $file_to_open ) = @_;

	if( defined $file_to_open ){
		$self->file( $file_to_open );
	}

##	print "DB:connect(): File as it currently exists: |". $self->file ."|\n";

	my $file = $self->file;

	if(
		!defined $file
		||
		$file eq ""
	){
		die("Database file not defined\n");
	}

	my $dbh = DBI->connect(
				"dbi:SQLite:dbname=". $file,
				"",
				"",
				{
					RaiseError => 1,
					AutoCommit => 1,
					PrintError => 0
				}
			);

	$self->_write_dbh( $dbh );


	#
	# Check if this is a new database, if so lets go ahead and set
	# it up and get it kicked off with an initial log position
	#

	my $sth = $dbh->table_info("", "%", 'transactions', "TABLE");
	if ( ! $sth->fetch) {
		# doesn't exist
		print "*** New Database, initializing and doing a file scan\n";

		$self->create_database();
#		FileSync::SyncDiff::Scanner->full_scan( $self->config, $self );
	}

	return;

	#
	# Beyond this is all random testing code
	#

##	print "----------------------------------\n";
##	print Dumper $dbh;
##	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my $select_all = $dbh->prepare("SELECT * FROM files");

	$select_all->execute();

	my $row_ref = $select_all->fetchall_hashref('id');

##	print "----------------------------------\n";
##	print Dumper \$row_ref;
##	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";
	
} # end connect()

#
# Need to override this from Forkable
#
override 'run_child' => sub {
	my( $self ) = @_;

	$self->recv_loop();
}; # end run_child();

sub recv_loop {
	my( $self ) = @_;

	my $PARENT_IPC = $self->PARENT_IPC;
	my $line = undef;

	while( $line = <$PARENT_IPC> ){
		chomp($line);
		my $response = $self->process_request( $line );

##		print "DB:recv_loop() - going to push response back at parent\n";

##		print Dumper $response;
##		print "DB:recv_loop() - pushing...\n";

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

		my $ref_resp = ref( $response );

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

##		print "Why is this a dud:\n";
##		print Dumper $response;

		my $json_response = encode_json( $response );
		print $PARENT_IPC $json_response ."\n";
	}
} # end recv_loop()

sub process_request {
	my( $self, $line ) = @_;

##	print "-----------------------\n";
##	print "DB:process_request - line:\n";
##	print Dumper $line;
##	print "^^^^^^^^^^^^^^^^^^^^^^^\n";
	my $request = decode_json( $line );

	if( ! defined $request->{operation} ){
		print "FileSync::SyncDiff::DB->process_request() - No Operation specified!\n";
		print Dumper $request;
		return;
	}

##	print "FileSync::SyncDiff::DB->process_request() - Operation: |". $request->{operation} ."|\n";

	if( $request->{operation} eq "new_transaction_id" ){
		return $self->_new_transaction_id( $request->{group}, $request->{transaction_id} );
	}

	if( $request->{operation} eq "lookup_file" ){
		return $self->_lookup_file( $request->{filename}, $request->{group}, $request->{groupbase} );
	}

	if( $request->{operation} eq "lookup_filelist" ){
		return $self->_lookup_filelist( $request->{group}, $request->{groupbase} );
	}

	if( $request->{operation} eq "getpwuid" ){
		return $self->_getpwuid( $request->{uid} );
	}

	if( $request->{operation} eq "getgrgid" ){
		return $self->_getgrgid( $request->{gid} );
	}
	if( $request->{operation} eq "add_file" ){
		return $self->_add_file( $request->{file} );
	}
	if( $request->{operation} eq "update_file" ){
		return $self->_update_file( $request->{file} );
	}
	if( $request->{operation} eq "mark_deleted" ){
		return $self->_mark_deleted( $request->{file} );
	}
	if( $request->{operation} eq "gethostbyname" ){
		return $self->_gethostbyname( $request->{hostname} );
	}
	if( $request->{operation} eq "current_log_position" ){
		return $self->_current_log_position();
	}
	if( $request->{operation} eq "set_remote_log_position" ){
		return $self->_set_remote_log_position( $request->{hostname}, $request->{group}, $request->{log_position} );
	}
	if( $request->{operation} eq "get_remote_log_position" ){
		return $self->_get_remote_log_position( $request->{hostname}, $request->{group} );
	}
	if( $request->{operation} eq "get_files_changed_since" ){
		return $self->_get_files_changed_since( $request->{group}, $request->{transactionid} );
	}
	if( $request->{operation} eq "getlocalhostname" ){
		return $self->_getlocalhostname();
	}

	if( $request->{operation} eq "clean_stop" ){
		return $self->_clean_stop();
	}

	if( $request->{operation} eq "delete_file" ){
		return $self->_delete_file( $request->{file} );
	}

	if( $request->{operation} eq "is_file_already_present"){
		return $self->_is_file_already_present( $request->{file_checksum} );
	}

	if ( $request->{operation} eq "is_file_soft_deleted"){
		return $self->_is_file_soft_deleted( $request->{file_checksum}, $request->{group}, $request->{groupbase} );
	}

	if ( $request->{operation} eq "add_or_update_file"){
		return $self->_add_or_update_file( $request->{file} );
	}

	if ( $request->{operation} eq "remove_soft_delete_entry"){
		return $self->_remove_soft_delete_entry( $request->{file_checksum}, $request->{group} );
	}

	if ( $request->{operation} eq "add_soft_delete_entry"){
		return $self->_add_soft_delete_entry( $request->{file_checksum}, $request->{group} );
	}

	if ( $request->{operation} eq "get_soft_deleted_files_to_clean"){
		return $self->_get_soft_deleted_files_to_clean( $request->{group} );
	}

} # end process_request()

sub clean_stop {
	my( $self ) = @_;

	my %request = (
		operation	=> 'clean_stop',
		);

	return $self->send_request( %request );
}

sub _clean_stop {
	my( $self ) = @_;
	my $dbh = $self->dbh;

	$dbh->disconnect();

	my $PARENT_IPC = $self->PARENT_IPC;

	my %temp_resp = (
		ZERO	=> "0",
	);
	my $response = \%temp_resp;

	my $json_response = encode_json( $response );
	print $PARENT_IPC $json_response ."\n";

	exit(0);
}

sub create_database {
	my( $self ) = @_;
	my $dbh = $self->dbh;

	$dbh->do("CREATE TABLE if not exists files (id INTEGER PRIMARY KEY AUTOINCREMENT, filepath TEXT, syncgroup TEXT, syncbase TEXT, filetype TEXT, inode_num INTEGER, perms INTEGER, uid INTEGER, username TEXT, gid INTEGER, groupname TEXT, size_bytes INTEGER, mtime INTEGER, extattr TEXT, checksum TEXT, deleted INTEGER, last_transaction TEXT)");

	$dbh->do("CREATE TABLE if not exists transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, transactionid TEXT, 'group' TEXT, timeadded INTEGER)");

	$dbh->do("CREATE TABLE servers_seen (id INTEGER PRIMARY KEY AUTOINCREMENT, hostname TEXT unique, transactionid TEXT, 'group' TEXT, timeadded INTEGER)");

	$dbh->do("CREATE TABLE if not exists soft_deleted_files (id INTEGER PRIMARY KEY AUTOINCREMENT, checksum TEXT, soft_deleted_since INTEGER, syncgroup TEXT)");

	my $transaction_id = sha256_hex( hostname() ."-". $$ ."-". time() );

	print Dumper $self->config->config;
	foreach my $group ( sort keys %{ $self->config->config->{groups} } ){
		print "Group: $group\n";
		$self->_new_transaction_id( $group, $transaction_id );
	}
} # end create_database()

sub send_request {
	my( $self, %request ) = @_;

##	print "FileSync::SyncDiff::DB->send_request() - Starting\n";
	my $json = encode_json( \%request );

	my $db_pipe = $self->CHILD_IPC;

##	print Dumper $db_pipe;

	print $db_pipe $json ."\n";

##	print "We sent the thing off, waiting for return\n";

	my $line = undef;

	while( $line = <$db_pipe> ){
		if( defined $line  ){
			chomp( $line );
			last if( $line ne "" );
		}
	}

##	print Dumper $line;
	if (defined $line) {
		chomp( $line );
	}

##	print "Got response\n";

##	print "*** DB->send_request() - return line:\n";
##	print Dumper $line;

	if (!(defined $line)) {
		return 0;
	}

	if( $line eq "0" ){
		return 0;
	}

	my $response = decode_json( $line );

	if( ref( $response ) eq "ARRAY" ){
		return $response;
	}

	if( defined $response->{ZERO} ){
		return 0;
	}

	if( defined $response->{SCALAR} ){
		return $response->{SCALAR};
	}

	return $response;
}

sub new_transaction_id {
	my( $self, $group, $transaction_id ) = @_;

##	print "FileSync::SyncDiff::DB->new_transaction_id() - Starting\n";

	my %request = (
		operation	=> 'new_transaction_id',
		group		=> $group,
		transaction_id	=> $transaction_id,
		);

	return $self->send_request( %request );
}

sub _new_transaction_id {
	my( $self, $group, $transaction_id ) = @_;
	my $dbh = $self->dbh;

##	print "~~~ Adding a transaction\n";

##	print Dumper $dbh;
##
##	print "^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my $add_transaction = $dbh->prepare("INSERT INTO transactions (`group`, transactionid, timeadded) VALUES( ?, ?, strftime('%s','now') )");
	$add_transaction->execute( $group, $transaction_id );

	return 0;
} # end _new_transaction_id()

sub _get_transaction_id {
	my( $self, $group, $transactionid ) = @_;
	my $dbh = $self->dbh;


	my $sth = $dbh->prepare("SELECT * FROM transactions WHERE transactionid=? and `group`=?");
	$sth->execute( $transactionid, $group );

	if ( $sth->err ){
		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $sth->fetchall_hashref('id');
	if( ( scalar ( keys %$row_ref ) ) == 0 ){
		return 0;
	}

	return $transactionid;
} # end _new_transaction_id()

sub lookup_file {
	my( $self, $filename, $group, $groupbase ) = @_;

	my %request = (
		operation	=> 'lookup_file',
		filename	=> $filename,
		group		=> $group,
		groupbase	=> $groupbase,
		);

	my $response = $self->send_request( %request );

##	print Dumper $response;

	return $response;
} #end lookup_file()

sub _lookup_file {
	my( $self, $filename, $group, $groupbase ) = @_;
	my $dbh = $self->dbh;

	my $lookup_file = $dbh->prepare("SELECT * FROM files WHERE filepath=? and syncgroup=? and syncbase=?");
	$lookup_file->execute( $filename, $group, $groupbase);

	if ( $lookup_file->err ){
#		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $lookup_file->fetchall_hashref('id');
	if( ( scalar ( keys %$row_ref ) ) == 0 ){
		return 0;
	}

	my $fileobj = FileSync::SyncDiff::File->new( dbref => $self );

	$fileobj->parse_dbrow( $row_ref );

	my %return_hash = $fileobj->to_hash();

	return \%return_hash;
} # end _lookup_file()

sub lookup_filelist {
	my( $self, $group, $groupbase ) = @_;

	my %request = (
		operation	=> 'lookup_filelist',
		group		=> $group,
		groupbase	=> $groupbase,
		);

	my $response = $self->send_request( %request );

##	print Dumper $response;

	my @filelist;

	foreach my $id ( sort keys %$response ){
##		print "Hash ID: ". $id ."\n";

		my $fileobj = FileSync::SyncDiff::File->new( dbref => $self );
		$fileobj->from_hash( $response->{$id} );

#		my %filehash = $fileobj->to_hash();
#
#		push( @filelist, \%filehash );
		push( @filelist, $fileobj );
	}

##	print Dumper \@filelist;

	return \@filelist;
} # end lookup_filelist()

sub _lookup_filelist {
	my( $self, $group, $groupbase ) = @_;
	my $dbh = $self->dbh;

	my $lookup_file = $dbh->prepare("SELECT * FROM files WHERE syncgroup=? and syncbase=? and deleted=0");
	$lookup_file->execute( $group, $groupbase);

	if ( $lookup_file->err ){
#		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $lookup_file->fetchall_hashref('id');

##	print "**** FILELIST\n";
##	print Dumper $row_ref;

	if( ( scalar ( keys %$row_ref ) ) == 0 ){
		return 0;
	}

	my %filelist_arr;
	my %return_hash;

#	foreach my $id ( sort keys %$row_ref ){
#		print "Hash ID: ". $id ."\n";
#		my $fileobj = FileSync::SyncDiff::File->new( dbref => $self );
#
#		$fileobj->parse_dbrow( $row_ref->{$id} );
#
#		%return_hash = $fileobj->to_hash();
#	}

	#return \%return_hash;
	return $row_ref;
} # end _lookup_filelist()

sub getpwuid {
	my( $self, $uid ) = @_;
	my %request = (
		operation	=> 'getpwuid',
		uid		=> $uid,
		);

	my $response = $self->send_request( %request );

	return (
		$response->{username},
		$response->{u_pass},
		$response->{u_uid},
		$response->{u_gid},
		$response->{u_quota},
		$response->{u_comment},
		$response->{u_gcos},
		$response->{u_dir},
		$response->{u_shell},
		$response->{u_expire},
		);
} # end getpwuid()

sub _getpwuid {
	my( $self, $uid ) = @_;

	my(
		$username,
		$u_pass,
		$u_uid,
		$u_gid,
		$u_quota,
		$u_comment,
		$u_gcos,
		$u_dir,
		$u_shell,
		$u_expire
	) = CORE::getpwuid( $uid );

	my %response = (
		username	=> $username,
		u_pass		=> $u_pass,
		u_uid		=> $u_uid,
		u_gid		=> $u_gid,
		u_quota		=> $u_quota,
		u_comment	=> $u_comment,
		u_gcos		=> $u_gcos,
		u_dir		=> $u_dir,
		u_shell		=> $u_shell,
		u_expire	=> $u_expire,
		);

	return \%response;
} # end _getpwuid()

sub getgrgid {
	my( $self, $gid ) = @_;

	my %request = (
		operation	=> 'getgrgid',
		gid		=> $gid,
		);

	my $response = $self->send_request( %request );

	return (
		$response->{groupname},
		$response->{g_passwd},
		$response->{g_gid},
		$response->{g_members},
		);
} # end getgrgid()

sub _getgrgid {
	my( $self, $gid ) = @_;

	my(
		$groupname,
		$g_passwd,
		$g_gid,
		$g_members,
	) = CORE::getgrgid( $gid );

	my %response = (
		groupname	=> $groupname,
		g_passwd	=> $g_passwd,
		g_gid		=> $g_gid,
		g_members	=> $g_members,
		);

	return \%response;
} # end _getpwuid()

sub add_file {
	my( $self, $file ) = @_;

	my %file_hash = $file->to_hash();

##	print "File hash:\n";
##	print Dumper \%file_hash;

	my %request = (
		operation	=> 'add_file',
		file		=> \%file_hash,
		);

	my $response = $self->send_request( %request );
} # end add_file()

sub _add_file {
	my( $self, $file ) = @_;
	my $dbh = $self->dbh;

##	print "------------------------\n";
##	print "DB->_add_file()\n";
##	print "------------------------\n";
##	print Dumper $file;
##	print "------------------------\n";

	my $file_obj = FileSync::SyncDiff::File->new(dbref => $self );

	$file_obj->from_hash( $file );
##	print Dumper \$file_obj;
##	print "^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my $new_file_sth =  $dbh->prepare("INSERT INTO files (filepath, syncgroup, syncbase, filetype, inode_num, perms, uid, username, gid, groupname, size_bytes, mtime, extattr, checksum, last_transaction, deleted) VALUES( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0 )");

	$new_file_sth->execute(
		$file_obj->filepath,
		$file_obj->syncgroup,
		$file_obj->syncbase,
		$file_obj->filetype,
		$file_obj->inode_num,
		$file_obj->mode,
		$file_obj->uid,
		$file_obj->username,
		$file_obj->gid,
		$file_obj->groupname,
		$file_obj->size_bytes,
		$file_obj->mtime,
		$file_obj->extattr,
		$file_obj->checksum,
		$file_obj->last_transaction
		);

	return 0;
} # end _add_file()

sub mark_deleted {
	my( $self, $file ) = @_;

	my %file_hash = $file->to_hash();

	my %request = (
		operation	=> 'mark_deleted',
		file		=> \%file_hash,
		);

	my $response = $self->send_request( %request );
} # end mark_deleted()

sub _mark_deleted {
	my( $self, $file ) = @_;
	my $dbh = $self->dbh;

	my $file_obj = FileSync::SyncDiff::File->new(dbref => $self );
	$file_obj->from_hash( $file );

##	print "Marking deleted:\n";
##	print "\tlast transaction: ". $file_obj->last_transaction ."\n";
##	print "\tFilepath: ". $file_obj->filepath ."\n";
##	print "\tsyncgroup: ". $file_obj->syncgroup ."\n";
##	print "\tsyncbase: ". $file_obj->syncbase ."\n";
	
	my $sql = "UPDATE files set last_transaction=?, deleted=1 WHERE filepath=? and syncgroup=? and syncbase=?";

##	print "\tSQL: ". $sql ."\n";

	my $mark_deleted_sth =  $dbh->prepare($sql);

	$mark_deleted_sth->execute(
		$file_obj->last_transaction,

		$file_obj->filepath,
		$file_obj->syncgroup,
		$file_obj->syncbase
		);

	if ( $mark_deleted_sth->err ){
		die "ERROR! return code: ". $mark_deleted_sth->err . " error msg: " . $mark_deleted_sth->errstr . "\n";
	}

	return 0;
} # end _mark_deleted()

sub delete_file {
	my( $self, $file ) = @_;

	my %file_hash = $file->to_hash();

	my %request = (
		operation	=> 'delete_file',
		file		=> \%file_hash,
		);

	my $response = $self->send_request( %request );
} # end delete_file()

sub _delete_file {
	my( $self, $file ) = @_;
	my $dbh = $self->dbh;

	my $file_obj = FileSync::SyncDiff::File->new(dbref => $self );
	$file_obj->from_hash( $file );

##	print "Marking deleted:\n";
##	print "\tlast transaction: ". $file_obj->last_transaction ."\n";
##	print "\tFilepath: ". $file_obj->filepath ."\n";
##	print "\tsyncgroup: ". $file_obj->syncgroup ."\n";
##	print "\tsyncbase: ". $file_obj->syncbase ."\n";

	my $sql = "DELETE FROM files WHERE filepath=? and syncgroup=? and syncbase=?";

##	print "\tSQL: ". $sql ."\n";

	my $delete_file_sth =  $dbh->prepare($sql);

	$delete_file_sth->execute(
		$file_obj->filepath,
		$file_obj->syncgroup,
		$file_obj->syncbase
		);

	if ( $delete_file_sth->err ){
		die "ERROR! return code: ". $delete_file_sth->err . " error msg: " . $delete_file_sth->errstr . "\n";
	}

	return 0;
} # end _delete_file()

sub update_file {
	my( $self, $file ) = @_;

	my %file_hash = $file->to_hash();

	my %request = (
		operation	=> 'update_file',
		file		=> \%file_hash,
		);

	my $response = $self->send_request( %request );
} # end update_file()

sub _update_file {
	my( $self, $file ) = @_;
	my $dbh = $self->dbh;

	my $file_obj = FileSync::SyncDiff::File->new(dbref => $self );

	$file_obj->from_hash( $file );

	my $new_file_sth =  $dbh->prepare("UPDATE files set filepath=?, syncgroup=?, syncbase=?, filetype=?, inode_num=?, perms=?, uid=?, username=?, gid=?, groupname=?, size_bytes=?, mtime=?, extattr=?, checksum=?, last_transaction=?, deleted=0 WHERE filepath=? and syncgroup=? and syncbase=?");

	$new_file_sth->execute(
		$file_obj->filepath,
		$file_obj->syncgroup,
		$file_obj->syncbase,
		$file_obj->filetype,
		$file_obj->inode_num,
		$file_obj->mode,
		$file_obj->uid,
		$file_obj->username,
		$file_obj->gid,
		$file_obj->groupname,
		$file_obj->size_bytes,
		$file_obj->mtime,
		$file_obj->extattr,
		$file_obj->checksum,
		$file_obj->last_transaction,

		$file_obj->filepath,
		$file_obj->syncgroup,
		$file_obj->syncbase
		);

	return 0;
} # end _update_file()

sub getlocalhostname {
	my( $self ) = @_;


	my %request = (
		operation	=> 'getlocalhostname',
		);

	my $response = $self->send_request( %request );
} # end getlocalhostname()

sub _getlocalhostname {
	my( $self ) = @_;

	return hostname();
}

sub gethostbyname {
	my( $self, $hostname ) = @_;

	my %request = (
		operation	=> 'gethostbyname',
		hostname	=> $hostname,
		);

	my $response = $self->send_request( %request );

} # end gethostbyname

sub _gethostbyname {
	my( $self, $hostname ) = @_;

	return inet_ntoa(inet_aton($hostname));
} # end _gethostbyname()

sub current_log_position {
	my( $self ) = @_;

	my %request = (
		operation	=> 'current_log_position',
		);

	print "Pushing request for current log position\n";

	my $response = $self->send_request( %request );

	print "Got response and it is...\n";
	print Dumper $response;
	return $response;
} # end current_log_position()

sub _current_log_position {
	my( $self ) = @_;
	my $dbh = $self->dbh;

	print "Got request for current log position\n";

	my $get_current_transaction_id = $dbh->prepare("select id, transactionid from transactions order by id desc limit 1;");
	$get_current_transaction_id->execute();

	if ( $get_current_transaction_id->err ){
		die "ERROR! return code: ". $get_current_transaction_id->err . " error msg: " . $get_current_transaction_id->errstr . "\n";
	}

	my $row_ref = $get_current_transaction_id->fetchall_hashref('id');
	print "Current Log position stuff:\n";
	print Dumper $row_ref;

	print "How many keys *ARE* there... ". ( scalar ( keys %{$row_ref} ) ) ."\n";
	if(
		( scalar ( keys %{$row_ref} ) ) == 0
		||
		( scalar ( keys %{$row_ref} ) ) > 1
	){
		return 0;
	}

	my $id;

	foreach $id ( sort keys %{$row_ref} ){
		print "Id is: $id\n";
		print "Hash is: ". $row_ref->{ $id }->{'transactionid'} ."\n";
		return $row_ref->{ $id }->{'transactionid'};
	}
} # end _current_log_position()

sub set_remote_log_position {
	my( $self, $hostname, $group, $log_position ) = @_;

	my %request = (
		operation	=> 'set_remote_log_position',
		hostname	=> $hostname,
		group		=> $group,
		log_position	=> $log_position,
		);

	my $response = $self->send_request( %request );

	return $response;
} # end set_remote_log_position()

sub _set_remote_log_position {
	my( $self, $hostname, $group, $transactionid ) = @_;
	my $dbh = $self->dbh;

	my $sth = $dbh->prepare("replace into servers_seen (hostname, transactionid, `group`, timeadded) values ( ?, ?, ?, strftime('%s','now') )");
	$sth->execute( $hostname, $transactionid, $group );

	if ( $sth->err ){
		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}


	return 0;
} # end _set_remote_log_position()

sub get_remote_log_position {
	my( $self, $hostname, $group ) = @_;

	my %request = (
		operation	=> 'get_remote_log_position',
		hostname	=> $hostname,
		group		=> $group
		);

	my $response = $self->send_request( %request );

	return $response;
} # end get_remote_log_position()

sub _get_remote_log_position {
	my( $self, $hostname, $group ) = @_;
	my $dbh = $self->dbh;

	print "Hostname: |$hostname| | Group: |$group|\n";

	my $sql = "SELECT id, transactionid FROM servers_seen WHERE hostname=? AND `group`=? order by id desc limit 1;";
	print "Sql: $sql\n";
	my $sth = $dbh->prepare($sql);
	$sth->execute($hostname, $group);

	if ( $sth->err ){
		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $sth->fetchall_hashref('id');
	print "Current Log position stuff:\n";
	print Dumper $row_ref;

	print "How many keys *ARE* there... ". ( scalar ( keys %{$row_ref} ) ) ."\n";
	if(
		( scalar ( keys %{$row_ref} ) ) == 0
		||
		( scalar ( keys %{$row_ref} ) ) > 1
	){
		return 0;
	}

	my $id;

	foreach $id ( sort keys %{$row_ref} ){
		print "Id is: $id\n";
		print "Hash is: ". $row_ref->{ $id }->{'transactionid'} ."\n";
		return $row_ref->{ $id }->{'transactionid'};
	}

} # end _get_remote_log_position()

sub get_files_changed_since {
	my( $self, $group, $transactionid ) = @_;

	my %request = (
		operation	=> 'get_files_changed_since',
		group		=> $group,
		transactionid	=> $transactionid,
		);

	my $response = $self->send_request( %request );

#	print "---------------------\n";
#	print "Response from _get_files_changed_since:\n";
#	print "---------------------\n";
#	print Dumper $response;
#	print "^^^^^^^^^^^^^^^^^^^^^\n";

	return $response;
} #end get_files_changed_since()

sub _get_files_changed_since {
	my( $self, $group, $transactionid ) = @_;
	my $dbh = $self->dbh;

	my $transaction_status = $self->_get_transaction_id( $group, $transactionid );

	my $sth = undef; 
	my $sql = undef;

	print "Transaction status: ". $transaction_status ."\n";

	if(
		$transaction_status eq "0"
		&&
		$transaction_status ne $transactionid
	){
		# Transaction wasn't found for this
		# group, lets assume we need to give it everything

		print "*** Transaction not found, should just send everything\n";
		$sql = "SELECT * FROM files WHERE syncgroup=?;";

		$sth = $dbh->prepare($sql);

		$sth->execute( $group );
	} else {
		# Transaction exists, and is in the right group
		# that's a bonus.  This means we can pick up a smaller
		# change set

		# unsurprisingly this is going to be ridiculously complex
		# sql statement with 3 sub parts

		$sql = "SELECT * FROM files WHERE last_transaction IN ( "
				." SELECT transactionid FROM transactions WHERE timeadded >= ( "
					." SELECT timeadded FROM transactions WHERE transactionid=? AND `group`=? "
				." ) "
			." ); ";

		print "Sql: |$sql|\n";

		$sth = $dbh->prepare($sql);

		$sth->execute( $transactionid, $group );
	}

	if ( $sth->err ){
		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $sth->fetchall_hashref('id');
	print "Files Found:\n";
	print Dumper $row_ref;

	my @return_array = ();
	my %return_hash = ();
	my $x = 0;

	foreach my $id ( sort keys %{$row_ref} ){
		print "Id is: $id\n";
		print "Hash is: ". $row_ref->{ $id }->{'last_transaction'} ."\n";

		my $temp_file_obj = FileSync::SyncDiff::File->new(dbref => $self);

		$temp_file_obj->from_hash( $row_ref->{ $id } );

		my %temp_file_hash = $temp_file_obj->to_hash();

		#push( @return_array, %temp_file_hash );
		$return_hash{$x} = \%temp_file_hash;
		$x = $x + 1;
	}

#	print "---------------------\n";
#	print "Files that have changed:\n";
#	print "---------------------\n";
#	#print Dumper \@return_array;
#	print Dumper \%return_hash;
#	print "^^^^^^^^^^^^^^^^^^^^^\n";

	#return \@return_array;
	return \%return_hash;
} # end _get_files_changed_since()

#sub is_file_already_present {
#	my( $self, $file_checksum ) = @_;
#	
#	my %request = (
#			operation => 'is_file_already_present',
#			file_checksum => $file_checksum,
#	);
#	my $response = Is_file_already_present;
#	my $response = $self->send_request( %request );
#
#	return $response;
#} # end is_file_already_present

sub is_file_already_present {
	my ( $self, $file_checksum) = @_;
	my $dbh = $self->dbh;

	my $sql = "SELECT * FROM files WHERE checksum=? ;";

	my $sth = $dbh->prepare($sql);
	$sth->execute($file_checksum);
	
	my @row = $sth->fetchrow_array();
	my @return_array = ($sth->rows, @row);
	
	return \@return_array;
} # end _is_file_already_present

sub is_file_soft_deleted {
	my( $self, $file_checksum, $group, $groupbase ) = @_;

	my %request = (
			operation => 'is_file_soft_deleted',
			group => $group,
			groupbase => $groupbase,
	);

	my $response = $self->send_request( %request );

	return $response;
} # end is_file_soft_deleted

sub _is_file_soft_deleted {
	my ($self, $file_checksum, $group, $groupbase) = @_;
	my $row_count = 0;

	if ( -e ($groupbase . "/.softDeleted/" . $file_checksum)) {			# keeping a default path temporarily
#		my $new_file_obj = FileSync::SyncDiff::File->new(dbref => FileSync::SyncDiff::DB->new(config => $self->config));
#		$new_file_obj->get_file( $groupbase . "/.softDeleted/" . $file_checksum, "", "");
#		$new_file_obj->checksum_file();
#		my $file_new_checksum = $new_file_obj->checksum;

#		if ($file_new_checksum == $file_checksum) {
			my $dbh = $self->dbh;
			my $sql = "SELECT * FROM soft_deleted_files WHERE checksum=? AND syncgroup=? ;";
			my $sth = $dbh->prepare($sql);
			$sth->execute($file_checksum, $group);
			my @row = $sth->fetchrow_array();
			$row_count = $sth->rows;
#		}
	}
	return $row_count;
} # end _is_file_soft_deleted

sub add_or_update_file {
	my ($self, $file) = @_;

	my %file_hash = $file->to_hash();

	my %request = (
			operation => 'add_or_update_file',
			file => \%file_hash,
	);

	my $response = $self->send_request( %request );
} # end add_or_update_file

sub _add_or_update_file {
	my ($self, $file) = @_;

	my $file_obj = FileSync::SyncDiff::File->new(dbref => $self );
	$file_obj->from_hash( $file );

	my $dbh = $self->dbh;
	my $sql = "SELECT * FROM files WHERE filepath=? and syncgroup=? and syncbase=? ;";
	my $sth = $dbh->prepare($sql);
	$sth->execute(
		$file_obj->filepath,
		$file_obj->syncgroup,
		$file_obj->syncbase
		);

	my @row = $sth->fetchrow_array();
	my $row_count = $sth->rows;

	if ($row_count == 0) {
		$self->_add_file($file_obj);
	}
	else {
		$self->_update_file($file_obj);
	}
} # end _add_or_update_file

sub remove_soft_delete_entry {
	my ($self, $file_checksum, $group) = @_;

	my %request = (
			operation => 'remove_soft_delete_entry',
			file_checksum => $file_checksum,
			group => $group,
	);

	my $response = $self->send_request( %request );
} # end remove_soft_delete_entry

sub _remove_soft_delete_entry {
	my ($self, $file_checksum, $group) = @_;

	my $dbh = $self->dbh;
	my $sql = "DELETE from soft_deleted_files WHERE checksum=? AND syncgroup=? ;";
	my $sth = $dbh->prepare($sql);
	$sth->execute($file_checksum, $group);
} # _remove_soft_delete_entry

sub add_soft_delete_entry {
	my ($self, $file_checksum, $group) = @_;

	my %request = (
			operation => 'add_soft_delete_entry',
			file_checksum => $file_checksum,
			group => $group,
	);

	my $response = $self->send_request( %request );
} # add_soft_delete_entry

sub _add_soft_delete_entry {
	my ($self, $file_checksum, $group) = @_;

	$self->_remove_soft_delete_entry($file_checksum, $group);	# remove the entry if already present

	my $dbh = $self->dbh;
	my $sql = "INSERT into soft_deleted_files (checksum, soft_deleted_since, syncgroup) values (?, strftime('%s','now'), ?) ;";
	my $sth = $dbh->prepare($sql);
	$sth->execute($file_checksum, $group);
} # end _add_soft_delete_entry

sub get_soft_deleted_files_to_clean {
	my ($self, $group ) = @_;

	my %request = (
		operation => 'get_soft_deleted_files_to_clean',
		group => $group,
	);

	my $response = $self->send_request( %request );

	return $response;
} # end get_soft_deleted_files_to_clean

sub _get_soft_deleted_files_to_clean {
	my ($self, $group) = @_;
	my $dbh = $self->dbh;
	my $TIME_RANGE = 30*24*60*60;

	my $sql = "SELECT checksum FROM soft_deleted_files WHERE soft_deleted_since<=? AND syncgroup=? ;";

	my $sth = $dbh->prepare($sql);
	$sth->execute(time() - $TIME_RANGE, $group);

	my @return_list = ();
	my $item;
	while (($item) = $sth->fetchrow_array()) {
		push(@return_list, $item);
	}
	return \@return_list;
} # end _get_soft_deleted_files_to_clean

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
