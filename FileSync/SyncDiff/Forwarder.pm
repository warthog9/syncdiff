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
use Net::Domain qw(domainname);
use HTTP::Response;
use JSON::XS qw(encode_json);

#
# Debugging
#
use Data::Dumper;

#
# moose variables
#
has 'dbref' => (
    is  => 'rw',
    isa => 'Object',
    required => 1,
);

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
            host  => inet_ntoa(inet_aton(domainname())),
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
            host  => inet_ntoa(inet_aton(domainname())),
            proto => 'tcp',
        }
    },
);

has 'response' => (
    is      => 'ro',
    isa     => 'HTTP::Response',
    default => sub {
        my ($code, $msg) = (200,'Success response!');
        return HTTP::Response->new($code,$msg);
    }

);

#
# constants
#
use constant {
    FIRST_PUBLIC_PORT => 1025,
    MAX_PORT_NUMBER   => 65535,
    TRY_PORT_LIMIT    => 10000,
};

sub run {
    my( $self ) = @_;
    if ( !$self->dbref->is_exists_connection($self->client) ) {
        if ( my $port = $self->_get_random_port() ) {
            $self->middleware->{port} = $port;
            my $content = encode_json({
                host => $self->middleware->{host},
                port => $port,
            });
            $self->response->content($content);
            $self->fork();
        }
    }
    else {
        $self->response->code(500);
        $self->response->message("Client's already connect");
    }

    return $self->response;
} # end run()

#
# Need to override this from Forkable
#

override 'run_child' => sub {
    my( $self ) = @_;

    $self->_forward();
}; # end run_child()

sub _get_random_port {
    my ( $self ) = @_;

    my $port   = undef;
    my $socket = undef;
    my $limit  = 0;
    do {
        $port = int( rand( MAX_PORT_NUMBER - FIRST_PUBLIC_PORT ) + FIRST_PUBLIC_PORT );
        $socket = eval {
            IO::Socket::INET->new(
                LocalPort => $port,
                Proto => 'tcp',
                Timeout => 1
                );
        };
        ++$limit;
    } until( $socket || $limit > TRY_PORT_LIMIT );

    close($socket) if ( defined $socket );

    return $port;
}

sub _forward {
    my ( $self ) = @_;

    my $listener = eval {
        IO::Socket::INET->new(
            LocalPort => $self->middleware->{port},
            Proto => $self->middleware->{proto},
            Listen => 2,
            ReuseAddr => 1
            );
    };
    if ($@) {
        print STDERR "Could not create socket $@";
        return undef;
    }

    $self->client->{port} = $self->middleware->{port};
    $self->dbref->new_connection($self->client);

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

        forward_sockets($client, $server);
    }

    return 1;
} # end _forward

__PACKAGE__->meta->make_immutable;

1;