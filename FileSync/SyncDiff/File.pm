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

package FileSync::SyncDiff::File;
$FileSync::SyncDiff::File::VERSION = '0.01';

use Moose;

#
#
#

use FileSync::SyncDiff::Util;
use FileSync::SyncDiff::DB;
use FileSync::SyncDiff::Log;

#
# Needed for the file scanning
#

use File::Spec;
use File::Basename;
use JSON::XS;

#
# Debugging
#

use Data::Dumper;

# End includes

#
# Local variables
#

has 'dbref' => (
		is	=> 'rw',
		isa	=> 'Object',
		required	=> 1,
		);

has 'path' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'filename' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'syncgroup' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'syncbase' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'filetype' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'inode_num' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'mode' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'uid' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'username' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'gid' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'groupname' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'size_bytes' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'mtime' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'extattr' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'checksum' => (
		is	=> 'rw',
		isa	=> 'Str',
		default	=> '',
		);

has 'last_transaction' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'deleted' => (
		is	=> 'rw',
		isa	=> 'Str',
		default => '0',
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
# End Local Variables
#

#
# Overloads
#

use overload '==' => \&_overload_comparison, fallback => 1;
use overload 'eq' => \&_overload_comparison, fallback => 1;

#
# End Overloads
#

sub _overload_comparison {
	my( $left, $right, $options ) = @_;

	for my $attr ( $left->meta->get_all_attributes ) {
		# TODO: Required attributes should be labeled
		next if ( $attr->type_constraint->name eq 'FileSync::SyncDiff::Log' );
		$left->log->debug("COMPARISON: %s", $attr->name);

		if( $attr->name eq "checksum" ){
			$left->log->debug("State of options: %s", ( defined $options ? 1 : 0 ));
			if( ref $options eq ref {} ){
				$left->log->debug("State of options->{checksum}: %s", ( ! defined $options->{checksum} ) );
			}
		}

		# Exclusions
		# 	Basically these entries
		# 	in the file object don't
		# 	matter for comparison

		if(
			$attr->name eq "inode_num"
			||
			$attr->name eq "last_transaction"
			||
			$attr->name eq "dbref"
			||
			(
				$attr->name eq "checksum"
				&&
				(
					ref $options ne ref {}
					||
					defined $options->{checksum}
				)
			)
		){
			next;
		}

		$left->log->debug("Left value: %s", $left->_get_file_attr_value( $attr->name ));
		$left->log->debug("Right value: %s", $right->_get_file_attr_value( $attr->name ));

		if(
			"". $left->_get_file_attr_value( $attr->name ) .""
			ne
			"". $right->_get_file_attr_value( $attr->name ) .""
		){
			return 0;
		}
	}

	return 1;
} # end _overload_comparison()

sub _get_file_attr_value {
	my( $self, $attr_name ) = @_;

	my $attr = $self->meta->get_attribute( $attr_name );
	my $ref = $attr->get_read_method;

	return $self->$ref;
} # end _file_attr_value

sub get_file {
	my( $self, $file, $group, $groupbase ) = @_;

	my(
		$dev,
		$ino,
		$mode,
		$nlink,
		$uid,
		$gid,
		$rdev,
		$size,
		$atime,
		$mtime,
		$ctime,
		$blksize,
		$blocks
	) = stat( $file );

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
	) = $self->dbref->getpwuid( $uid );
	my(
		$groupname,
		$g_passwd,
		$g_gid,
		$g_members
	) = $self->dbref->getgrgid( $gid );

	my $filetype;

	if( -f $file ){
		$filetype = 'file';
	} elsif( -d $file ){
		$filetype = 'dir';
	}

	my ( $filename, $path, $suffix ) = fileparse($file);
	$self->filename( $filename );
	$self->path( $path );
	$self->syncgroup( $group );
	$self->syncbase( $groupbase );
	$self->filetype( $filetype);
	$self->inode_num( $ino );
	$self->mode( $mode );
	$self->uid( $uid );
	$self->username( $username );
	$self->gid( $gid );
	$self->groupname( $groupname );
	$self->size_bytes( $blksize );
	$self->mtime( $mtime );
	$self->extattr( '' );
	#$self->checksum;
	#$self->last_transaction;
} # end get_file()

sub checksum_file {
	my( $self ) = @_;

	if( $self->filetype ne "file" ){
		return;
	}

	$self->log->debug("Checksumming: | %s |", $self->filepath);
	open(FILE, $self->filepath ) or die "ERROR. $_ could not be opened: $!";
	# This is critical to prevent ulcers and create correct SHA256 checksums
	binmode(FILE);

	# Compute the SHA256 of the file
	my $digest = Digest::SHA->new(256);
	$digest->addfile(*FILE);
	my $checksum = $digest->hexdigest();

	my $return = "sha256:". $checksum;

	$self->log->debug("Checksum: returning | %s |", $return);

	$self->checksum( $return );
} # end checksum_file()

sub filepath {
	my( $self ) = @_;

	if( $self->path eq "./" ){
		return $self->filename;
	}
	return File::Spec->catfile( $self->path, $self->filename );
} # end filepath()

sub parse_dbrow {
	my( $self, $db_row ) = @_;

	foreach my $row ( sort keys %{ $db_row } ){
		$self->from_hash( $db_row->{$row} );
	}
} # end parse_dbrow()

sub to_hash {
	my( $self ) = @_;

	my %file_hash = (
		path		=> $self->path,
		filename	=> $self->filename,
		syncgroup	=> $self->syncgroup,
		syncbase	=> $self->syncbase,
		filetype	=> $self->filetype,
		inode_num	=> $self->inode_num,
		mode		=> $self->mode,
		uid		=> $self->uid,
		username	=> $self->username,
		gid		=> $self->gid,
		groupname	=> $self->groupname,
		size_bytes	=> $self->size_bytes,
		mtime		=> $self->mtime,
		extattr		=> $self->extattr,
		checksum	=> $self->checksum,
		last_transaction	=> $self->last_transaction,
		deleted		=> $self->deleted,
		);

	return %file_hash;
} # end to_hash()

sub from_hash {
	my( $self, $file_hash ) = @_;
	$self->path( $file_hash->{path} ) if( defined $file_hash->{path} );
	$self->filename( $file_hash->{filename} ) if( defined $file_hash->{filename} );

	if( defined $file_hash->{filepath} ){
		my $path = dirname( $file_hash->{filepath} );
		$path = $path ."/";
		$path =~ s/\/+$/\//g;
		my $filename = basename( $file_hash->{filepath} );
		$self->path( $path );
		$self->filename( $filename );
	}

	$self->syncgroup( $file_hash->{syncgroup} );
	$self->syncbase( $file_hash->{syncbase} );
	$self->filetype( $file_hash->{filetype} );
	$self->inode_num( $file_hash->{inode_num} );

	$self->mode( $file_hash->{mode} ) if( defined $file_hash->{mode} );
	$self->mode( $file_hash->{perms} ) if( defined $file_hash->{perms} );

	$self->uid( $file_hash->{uid} );
	$self->username( $file_hash->{username} );
	$self->gid( $file_hash->{gid} );
	$self->groupname( $file_hash->{groupname} );
	$self->size_bytes( $file_hash->{size_bytes} );
	$self->mtime( $file_hash->{mtime} );
	$self->extattr( $file_hash->{extattr} );
	$self->checksum( $file_hash->{checksum} );
	$self->last_transaction( $file_hash->{last_transaction} );
	$self->deleted( $file_hash->{deleted} ) if( defined $file_hash->{deleted} );
} # end from_hash()

__PACKAGE__->meta->make_immutable;

1;
