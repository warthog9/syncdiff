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

has _fs          => ( is => 'rw', isa => 'HashRef', );
has _watcher     => ( is => 'rw', );

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
            my $file        = $self->_fs->{$kevent->[KQ_IDENT]}{file};
            my $groupbase   = $self->_fs->{$kevent->[KQ_IDENT]}{groupbase};
            $self->handle_event($file, $kevent, $groupbase);
        }
    );
}

sub BUILD {
    my $self = shift;

    # scan all directory in all groupbases
    my $fhs = $self->scan_fs();

    $self->_watcher( { fhs => $fhs, w => $self->io_watcher } );

    $self->_check_filehandle_count();

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

my $fs;

sub scan_fs {
    my ( $self ) = shift;

    my @fhs;
    for my $path ( @{$self->includes} ) {
        push @fhs, $self->_watch_dir($path);
    }

    return \@fhs;
}

sub _watch_dir {
    my ( $self, $include ) = @_;

    my $next = File::Next::files({
        sort_files => \&File::Next::sort_standard,
    }, $include);

    my @fhs;
    while ( my $entry = $next->() ) {
        last unless defined $entry;

        $entry = file($entry);

        open my $fh, '<', $entry->stringify || do {
            carp
              "KQueue requires a filehandle for each watched file on directory.\n"
              . "You have exceeded the number of filehandles permitted by the OS.\n"
              if $! =~ /^Too many open files/;
            confess "Can't open file ($entry->stringify): $!";
        };

        $self->kqueue->EV_SET(
            fileno($fh),
            EVFILT_VNODE,
            EV_ADD | EV_ENABLE | EV_CLEAR,
            NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB | NOTE_LINK |
              NOTE_RENAME | NOTE_REVOKE,
        );

        $fs->{fileno($fh)} = { file       => $entry->stringify,
                               groupbase  => $include,
                             }) if ! exists $fs->{fileno($fh)};
        push(@fhs, $fh);
    }

    $self->_fs($fs);

    return @fhs;
}

my %events = (
    &NOTE_EXTEND        => 'handle_modify',
    &NOTE_WRITE         => 'handle_modify',
);

sub handle_event {
    my ($self, $file, $event, $groupbase) = @_;

    for my $type (keys %events){
        my $method = $events{$type};
        if( $event->[KQ_FFLAGS] & $type ){
            $self->$method($file, $groupbase);
            return 1;
        }
    }
}

1;