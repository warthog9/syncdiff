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

package FileSync::SyncDiff::Notify::Plugin::Inotify2;
$FileSync::SyncDiff::Plugin::Inotify2::VERSION = '0.01';

use Moose;

use MooseX::Types::Moose qw(CodeRef);
use MooseX::Types -declare => ['Event'];
use MooseX::FileAttribute;

use FileSync::SyncDiff::Notify::Event;
use FileSync::SyncDiff::Notify::Event::Callback;

use AnyEvent;
use Linux::Inotify2;
use File::Next;

use Data::Dumper;

use namespace::clean -except => ['meta'];

has 'dirs' => ( 
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

has 'inotify' => (
    init_arg   => undef,
    is         => 'ro',
    isa        => 'Linux::Inotify2',
    handles    => [qw/poll fileno watch/],
    lazy_build => 1,
);

sub _build_inotify {
    my $self = shift;

    Linux::Inotify2->new or confess "Inotify initialization failed: $!";
}

has 'io_watcher' => (
    init_arg => undef,
    is       => 'ro',
    builder  => '_build_io_watcher',
    required => 1,
);

sub _build_io_watcher {
    my $self = shift;

    return AnyEvent->io(
        fh   => $self->fileno,
        poll => 'r',
        cb   => sub { $self->poll },
    );
}

sub _watch_dir {
    my ($self, $dir) = @_;

    my $next = File::Next::dirs({
        follow_symlinks => 0,
    }, $dir);

    while ( my $entry = $next->() ) {
        last unless defined $entry;

        if( -d $entry ){
            $entry = Path::Class::dir($entry);
        }
        else {
            $entry = Path::Class::file($entry);
        }

        $self->watch(
            $entry->stringify,
            IN_MODIFY,
            sub { $self->handle_event($entry, $_[0], $dir) },
        );
    }
}

sub BUILD {
    my $self = shift;

    $self->_watch_dir($_)for(@{$self->dirs});
}

my %events = (
    IN_MODIFY        => 'handle_modify',
);

sub handle_event {
    my ($self, $file, $event, $dir) = @_;

    my $event_file = $file->file($event->name);

    my $rel = $event_file->relative($dir);
    for my $type (keys %events){
        my $method = $events{$type};
        if( $event->$type ){
            $self->$method($rel, $dir);
        }
    }
}

1;