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

package FileSync::SyncDiff::Notify::Plugin::FSEvents;
$FileSync::SyncDiff::Plugin::FSEvents::VERSION = '0.01';

use Moose;
use MooseX::Types::Moose qw(CodeRef);
use MooseX::Types -declare => ['Event'];
use MooseX::FileAttribute;
use namespace::clean -except => ['meta'];

use FileSync::SyncDiff::Notify::Event;
use FileSync::SyncDiff::Notify::Event::Callback;

use Carp qw(confess carp);
use Mac::FSEvents;
use AnyEvent;
use File::Next;
use Path::Class;

use Data::Dumper;

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

has 'fsevents' => (
    init_arg   => undef,
    is         => 'ro',
    isa        => 'Mac::FSEvents',
    builder    => '_build_fsevents',
    lazy_build => 1,
);

has '_fs'      => (
    init_arg   => undef,
    is         => 'rw',
    isa        => 'HashRef',
    default    => sub { {} },
);

has '_watcher' => (
    init_arg   => undef,
    is         => 'rw',
);

sub _build_fsevents {
    my $self = shift;
}

sub _build_io_watcher {
    my $self = shift;
}

sub BUILD {
    my $self = shift;

    return 1;
}

1;