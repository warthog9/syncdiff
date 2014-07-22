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

package FileSync::SyncDiff::Notify::Plugin::KQueue;
$FileSync::SyncDiff::Plugin::KQueue::VERSION = '0.01';

use Moose;
use MooseX::Types::Moose qw(CodeRef);
use MooseX::Types -declare => ['Event'];
use MooseX::FileAttribute;
use namespace::clean -except => ['meta'];

use FileSync::SyncDiff::Notify::Event;
use FileSync::SyncDiff::Notify::Event::Callback;

use Carp qw(confess carp);
use IO::KQueue;
use AnyEvent;
use File::Next;
use Path::Class;

use Data::Dumper;

# Arbitrary limit on open filehandles before issuing a warning
our $WARN_FILEHANDLE_LIMIT = 50;

has 'includes' => (
    is         => 'ro',
    isa        => 'ArrayRef',
    required => 1,
);

role_type Event, { role => 'FileSync::SyncDiff::Notify::Event' };

coerce Event, from CodeRef, via {
    FileSync::SyncDiff::Notify::Event::Callback->new(
        callback => $_,
    ),
};

has 'event_receiver' => (
    is       => 'ro',
    isa      => Event,
    handles  => 'FileSync::SyncDiff::Notify::Event',
    required => 1,
    coerce   => 1,
);

has 'io_watcher' => (
    init_arg => undef,
    is       => 'ro',
    builder  => '_build_io_watcher',
    required => 1,
);

has 'kqueue' => (
    init_arg   => undef,
    is         => 'ro',
    isa        => 'IO::KQueue',
    builder    => '_build_kqueue',
    lazy_build => 1,
);

has '_fs'      => (
    init_arg   => undef,
    is         => 'rw',
    isa        => 'HashRef',
);

has '_watcher' => (
    init_arg   => undef,
    is         => 'rw',
);

sub _build_kqueue {
    my $self = shift;

    IO::KQueue->new() || confess "Unable to create new IO::KQueue object";
}

sub _build_io_watcher {
    my $self = shift;

    return AnyEvent->io (
        fh   => ${$self->kqueue},
        poll => 'r',
        cb   => sub {
            my $kevent      = $self->kqueue->kevent;
            my $fflags      = $kevent->[KQ_FFLAGS];
            my $groupbase   = $self->_fs->{$kevent->[KQ_IDENT]}{groupbase};
            my $fh          = $self->_fs->{$kevent->[KQ_IDENT]}{fh};
            my $file        = $self->_fs->{$kevent->[KQ_IDENT]}{file};
            $self->handle_event($file, $groupbase, $fflags, $fh);
        }
    );
}

sub BUILD {
    my $self = shift;

    # scan all directory in all groupbases
    my $fhs = $self->scan_fs($self->includes);

    return 1;
}

sub _check_filehandle_count {
    my ($self) = @_;

    my $count = $self->_watcher_count;
    carp "KQueue requires a filehandle for each watched file and directory.\n"
      . "You currently have $count filehandles for this object.\n"
      if $count > $WARN_FILEHANDLE_LIMIT;
}

sub _watcher_count {
    my ($self) = @_;
    return scalar @{ $self->_watcher->{fhs} };
}

sub scan_fs {
    my ( $self, $dirs ) = @_;

    my @fhs;
    for my $path ( @{$dirs} ) {
        push @fhs, $self->_watch_dir($path);
    }

    $self->_watcher( { fhs => \@fhs, w => $self->io_watcher } );

    $self->_check_filehandle_count();

    return 1;
}

sub _get_fhs {
    my $self = shift;
    my @fhs;
    while ( my($k,$v) = each(%{ $self->_fs }) ) {
        push @fhs, $v->{fh};
    }

    return @fhs;
}

sub _check_fs {
    my ( $self, $path ) = @_;
    my @items = grep{ $_->{file} eq $path } values(%{ $self->_fs }) if $self->_fs;
    return \@items;
}

sub _del_and_close {
    my ($self, $fh) = @_;
    delete $self->_fs->{fileno($fh)};
    close $fh;

    return 1;
}

# empty value need to proof validation of Moose HashRef
my $fs = {};

sub _watch {
    my ( $self, $o ) = @_;

    open my $fh, "<" ,$o->{path} || do {
            carp
              "KQueue requires a filehandle for each watched file and directory.\n"
              . "You have exceeded the number of filehandles permitted by the OS.\n"
              if $! =~ /^Too many open files/;
            confess "Can't open ($o->{path}): $!";
    };
    $self->kqueue->EV_SET(
            fileno($fh),
            EVFILT_VNODE,
            EV_ADD | EV_ENABLE | EV_CLEAR,
            NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_RENAME | NOTE_REVOKE,
    );

    $fs->{fileno($fh)}{fh}          = $fh;
    $fs->{fileno($fh)}{file}        = $o->{path};
    $fs->{fileno($fh)}{dir}         = 1 if -d $o->{path};
    $fs->{fileno($fh)}{groupbase}   = $o->{include} ? $o->{include} : $o->{path};

    return 1;
}

sub _watch_dir {
    my ( $self, $include ) = @_;

    my $next = File::Next::files({
        sort_files => \&File::Next::sort_standard,
    }, $include);

    # need to open a directories for detect a creation of files
    $self->_watch({path => $include}) if ( ! @{ $self->_check_fs($include) } );

    NEXT_FILE:
    while ( my $entry = $next->() ) {
        last unless defined $entry;

        $entry = file($entry);

        next NEXT_FILE if ( @{ $self->_check_fs($entry->stringify) } );

        $self->_watch({ path    => $entry->stringify,
                        include => $include,
        });
    }

    $self->_fs($fs);

    return $self->_get_fhs();
}

my %events = (
    &NOTE_EXTEND        => 'handle_modify',
    &NOTE_WRITE         => 'handle_modify',
);

sub handle_event {
    my ($self, $file, $groupbase, $fflags, $fh) = @_;

    if ( $fflags & NOTE_DELETE ) {
        $self->_del_and_close($fh);
        return 1;
    }
    elsif ( $fflags & NOTE_RENAME ) {
        $self->_del_and_close($fh);
        $self->scan_fs([$groupbase]);
        return 1;
    }

    for my $type (keys %events){
        my $method = $events{$type};
        if( $fflags & $type ){
            if ( $self->_fs->{fileno($fh)}{dir} ) {
                $self->scan_fs([$groupbase]);
            }
            else {
                $self->$method($file, $groupbase);
            }
            return 1;
        }
    }
}

1;