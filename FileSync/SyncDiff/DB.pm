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
use FileSync::SyncDiff::Log;

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

has 'log' => (
		is => 'rw',
		isa => 'FileSync::SyncDiff::Log',
		default => sub {
			my $self = shift;
			return FileSync::SyncDiff::Log->new( config => $self->config );
		}
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
		print STDERR "*** New Database, initializing and doing a file scan\n";

		$self->create_database();
	}

	return;

	#
	# Beyond this is all random testing code
	#

	my $select_all = $dbh->prepare("SELECT * FROM files");

	$select_all->execute();

	my $row_ref = $select_all->fetchall_hashref('id');
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

		if(
			$response eq "0"
		){
			my %temp_resp = (
				ZERO	=> "0",
			);
			$response = \%temp_resp;
		}

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

		my $json_response = encode_json( $response );
		print $PARENT_IPC $json_response ."\n";
	}
} # end recv_loop()

sub process_request {
	my( $self, $line ) = @_;

	my $request = decode_json( $line );

	if( ! defined $request->{operation} ){
		print STDERR "FileSync::SyncDiff::DB->process_request() - No Operation specified!\n";
		print STDERR Dumper $request;
		return;
	}

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

	$dbh->do("CREATE TABLE if not exists connections (id INTEGER PRIMARY KEY AUTOINCREMENT, host TEXT, port TEXT, auth_key TEXT, syncbase TEXT, timeadded INTEGER)");

	my $transaction_id = sha256_hex( hostname() ."-". $$ ."-". time() );

	print STDERR Dumper $self->config->config;
	foreach my $group ( sort keys %{ $self->config->config->{groups} } ){
		print STDERR "Group: $group\n";
		$self->_new_transaction_id( $group, $transaction_id );
	}
} # end create_database()

sub send_request {
	my( $self, %request ) = @_;

	my $json = encode_json( \%request );

	my $db_pipe = $self->CHILD_IPC;

	print $db_pipe $json ."\n";

	my $line = undef;

	while( $line = <$db_pipe> ){
		if( defined $line  ){
			chomp( $line );
			last if( $line ne "" );
		}
	}

	chomp( $line );

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

sub new_connection {
	my ($self,$info) = @_;
	my $dbh = $self->dbh;

	my $res = eval {
		my $add_connection = $dbh->prepare("INSERT INTO connections (host, port, auth_key, syncbase, timeadded) VALUES( ?, ?, ?, ?, strftime('%s','now') )");
		$add_connection->execute( $info->{host}, $info->{port}, $info->{auth_key}, $info->{syncbase} ) || die $DBI::errstr;
	};
	if ($@) {
		print STDERR "Error on add new connection: $@";
	}

	return $res;
}

sub clean_connections {
	my ($self,$info) = @_;
	my $dbh = $self->dbh;

	my $sql    = qq{ DELETE FROM connections };
	my @params = ();
	if ( defined $info ) {
		push @params, { $info->{host} => 'host = ?' }			if ( exists $info->{host} );
		push @params, { $info->{port} => 'port = ?' }			if ( exists $info->{port} );
		push @params, { $info->{auth_key} => 'auth_key = ?' }	if ( exists $info->{auth_key} );
		push @params, { $info->{syncbase} => 'syncbase = ?' }	if ( exists $info->{syncbase} );
		if ( scalar @params > 0 ){
			$sql .= qq{ WHERE };
			$sql .= join( ' AND ', map { values %{$_} }@params );
		}
	}

	my $res = eval {
		my $del_connection = $dbh->prepare($sql);
		$del_connection->execute( map { keys %{$_} }@params ) || die $DBI::errstr;
	};
	if ($@) {
		print STDERR "Error on clean up connections: $@";
	}

	return $res;
}

sub is_exists_connection {
	my ($self,$info) = @_;
	my $dbh = $self->dbh;

	my $sth = $dbh->prepare("SELECT * FROM connections WHERE host = ? AND auth_key = ? AND syncbase = ?");
	$sth->execute( $info->{host}, $info->{auth_key}, $info->{syncbase} ) || die $DBI::errstr;

	my $row_ref = $sth->fetchall_hashref('id');
	if( scalar ( keys %$row_ref ) != 0 ){
		return 1;
	}

	return 0;
}

sub new_transaction_id {
	my( $self, $group, $transaction_id ) = @_;

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

	my @filelist;

	foreach my $id ( sort keys %$response ){

		my $fileobj = FileSync::SyncDiff::File->new( dbref => $self );
		$fileobj->from_hash( $response->{$id} );

		push( @filelist, $fileobj );
	}

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

	if( ( scalar ( keys %$row_ref ) ) == 0 ){
		return 0;
	}

	my %filelist_arr;
	my %return_hash;

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

	my %request = (
		operation	=> 'add_file',
		file		=> \%file_hash,
		);

	my $response = $self->send_request( %request );
} # end add_file()

sub _add_file {
	my( $self, $file ) = @_;
	my $dbh = $self->dbh;

	my $file_obj = FileSync::SyncDiff::File->new(dbref => $self );

	$file_obj->from_hash( $file );

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

	my $sql = "UPDATE files set last_transaction=?, deleted=1 WHERE filepath=? and syncgroup=? and syncbase=?";

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

	print STDERR "Pushing request for current log position\n";

	my $response = $self->send_request( %request );

	print STDERR "Got response and it is...\n";
	print STDERR Dumper $response;
	return $response;
} # end current_log_position()

sub _current_log_position {
	my( $self ) = @_;
	my $dbh = $self->dbh;

	print STDERR "Got request for current log position\n";

	my $get_current_transaction_id = $dbh->prepare("select id, transactionid from transactions order by id desc limit 1;");
	$get_current_transaction_id->execute();

	if ( $get_current_transaction_id->err ){
		die "ERROR! return code: ". $get_current_transaction_id->err . " error msg: " . $get_current_transaction_id->errstr . "\n";
	}

	my $row_ref = $get_current_transaction_id->fetchall_hashref('id');
	print STDERR "Current Log position stuff:\n";
	print STDERR Dumper $row_ref;

	print STDERR "How many keys *ARE* there... ". ( scalar ( keys %{$row_ref} ) ) ."\n";
	if(
		( scalar ( keys %{$row_ref} ) ) == 0
		||
		( scalar ( keys %{$row_ref} ) ) > 1
	){
		return 0;
	}

	my $id;

	foreach $id ( sort keys %{$row_ref} ){
		print STDERR "Id is: $id\n";
		print STDERR "Hash is: ". $row_ref->{ $id }->{'transactionid'} ."\n";
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

	print STDERR "Hostname: |$hostname| | Group: |$group|\n";

	my $sql = "SELECT id, transactionid FROM servers_seen WHERE hostname=? AND `group`=? order by id desc limit 1;";
	print STDERR "Sql: $sql\n";
	my $sth = $dbh->prepare($sql);
	$sth->execute($hostname, $group);

	if ( $sth->err ){
		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $sth->fetchall_hashref('id');
	print STDERR "Current Log position stuff:\n";
	print STDERR Dumper $row_ref;

	print STDERR "How many keys *ARE* there... ". ( scalar ( keys %{$row_ref} ) ) ."\n";
	if(
		( scalar ( keys %{$row_ref} ) ) == 0
		||
		( scalar ( keys %{$row_ref} ) ) > 1
	){
		return 0;
	}

	my $id;

	foreach $id ( sort keys %{$row_ref} ){
		print STDERR "Id is: $id\n";
		print STDERR "Hash is: ". $row_ref->{ $id }->{'transactionid'} ."\n";
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

	return $response;
} #end get_files_changed_since()

sub _get_files_changed_since {
	my( $self, $group, $transactionid ) = @_;
	my $dbh = $self->dbh;

	my $transaction_status = $self->_get_transaction_id( $group, $transactionid );

	my $sth = undef; 
	my $sql = undef;

	print STDERR "Transaction status: ". $transaction_status ."\n";

	if(
		$transaction_status eq "0"
		&&
		$transaction_status ne $transactionid
	){
		# Transaction wasn't found for this
		# group, lets assume we need to give it everything

		print STDERR "*** Transaction not found, should just send everything\n";
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

		print STDERR "Sql: |$sql|\n";

		$sth = $dbh->prepare($sql);

		$sth->execute( $transactionid, $group );
	}

	if ( $sth->err ){
		die "ERROR! return code: ". $sth->err . " error msg: " . $sth->errstr . "\n";
	}

	my $row_ref = $sth->fetchall_hashref('id');
	print STDERR "Files Found:\n";
	print STDERR Dumper $row_ref;

	my @return_array = ();
	my %return_hash = ();
	my $x = 0;

	foreach my $id ( sort keys %{$row_ref} ){
		print STDERR "Id is: $id\n";
		print STDERR "Hash is: ". $row_ref->{ $id }->{'last_transaction'} ."\n";

		my $temp_file_obj = FileSync::SyncDiff::File->new(dbref => $self);

		$temp_file_obj->from_hash( $row_ref->{ $id } );

		my %temp_file_hash = $temp_file_obj->to_hash();

		$return_hash{$x} = \%temp_file_hash;
		$x = $x + 1;
	}

	return \%return_hash;
} # end _get_files_changed_since()

__PACKAGE__->meta->make_immutable;

1;
