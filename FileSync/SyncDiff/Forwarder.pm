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

package FileSync::SyncDiff::Forwarder;
$FileSync::SyncDiff::Forwarder::VERSION = '0.01';

use Moose;

extends 'FileSync::SyncDiff::Forkable';

#
# Other Includes
#
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Forwarder qw(forward_sockets);
use Sys::Hostname;

#
# Debugging
#
use Data::Dumper;

#
# moose variables
#

has 'client' => (
    is       => 'rw',
    isa      => 'HashRef',
    required => 1,
);

has 'server' => (
    is       => 'rw',
    isa      => 'HashRef',
    required => 1,
    default  => sub {
        {
            port  => '7070',
            host  => inet_ntoa(inet_aton(hostname())),
            proto => 'tcp',
        }
    },
);

has 'middleware' => (
    is       => 'rw',
    isa      => 'HashRef',
    default  => sub {
        {
            port  => '7069',
            host  => inet_ntoa(inet_aton(hostname())),
            proto => 'tcp',
        }
    },
);

sub run {
    my( $self ) = @_;

    $self->fork();
} # end run()

#
# Need to override this from Forkable
#

override 'run_child' => sub {
    my( $self ) = @_;

    $self->_forward();
}; # end run_child()

sub _forward {
    my ( $self ) = @_;

    my $listener = eval {
        IO::Socket::INET->new(
            LocalPort => $self->middleware->{port},
            LocalAddr => $self->middleware->{host},
            Proto => $self->middleware->{proto},
            Listen => 2,
            ReuseAddr => 1
            );
    };
    if ($@) {
        print STDERR "Could not create socket $@";
        return undef;
    }

    while ( 1 ) {
        my $client = $listener->accept();
        my $server = eval {
            IO::Socket::INET->new(
                PeerAddr => $self->server->{host},
                PeerPort => $self->server->{port},
                Proto => $self->server->{proto},
                );
        };
        if( !$server || $@ ){
            print STDERR "Could not connect to syncdiff server: $@\n";
            return undef;
        }

        $server->autoflush(1);

        forward_sockets($client, $server, debug => 1);
    }

    return 1;
} # end _forward

__PACKAGE__->meta->make_immutable;

1;