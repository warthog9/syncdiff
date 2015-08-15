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

use FileSync::SyncDiff::Log;

#
# Other Includes
#
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Forwarder qw(forward_sockets);
use Net::Domain qw(domainname);
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
    init_arg => undef,
    lazy     => 1,
    default  => sub {
        {
            port  => '7069',
            host  => inet_ntoa(inet_aton(domainname())),
            proto => 'tcp',
        }
    },
);

has 'response' => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    lazy     => 1,
    writer   => '_response',
    default  => sub { {} },
);

has 'log' => (
        is => 'rw',
        isa => 'FileSync::SyncDiff::Log',
        default => sub {
            return FileSync::SyncDiff::Log->new();
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

#----------------------------------------------------------------------
#** @method public run ($self)
# @brief Run forwarding beetween client and server
# @return HashRef, Forwarding response
# code - response code
# content_type - type of content
# content - content in appropriate format
#*
sub run {
    my( $self ) = @_;
    my $response = {};
    if ( !$self->dbref->is_exists_connection($self->client) ) {
        if ( my $port = $self->_get_random_port() ) {
            $self->middleware->{port} = $port;
            my $content = encode_json({
                host => $self->middleware->{host},
                port => $port,
            });
            $response = {
                code         => 200,
                content_type => 'application/json',
                content      => $content,
            };

            $self->fork();
        }
    }
    else {
        $response = {
            code         => 500,
            content_type => 'application/json',
        };
    }
    $self->_response($response);

    return $self->response;
} # end run()

#
# Need to override this from Forkable
#

override 'run_child' => sub {
    my( $self ) = @_;

    # Single client process - single forward connection
    $self->_forward();
}; # end run_child()

#----------------------------------------------------------------------
#** @method private _get_random_port ($self)
# @brief Return a random port from FIRST_PUBLIC_PORT to MAX_PORT_NUMBER
# @return scalar port
#*
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

#----------------------------------------------------------------------
#** @method private _forward($self)
# @brief Create a forward connection beetween server and client
# @return scalar, True value in success
#*
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
    if ( !$listener ) {
        $self->log->fatal("Could not create socket %s", $!);
    }

    $self->middleware->{socket} = $listener;
    $self->client->{port} = $self->middleware->{port};
    $self->dbref->new_connection($self->client);

    my $client = $listener->accept();
    my $server = eval {
        IO::Socket::INET->new(
            PeerAddr => $self->server->{host},
            PeerPort => $self->server->{port},
            Proto => $self->server->{proto},
            );
    };
    if( !$server ){
        $self->log->fatal("Could not connect to syncdiff server: %s", $!);
    }

    $self->server->{socket} = $server;
    $server->autoflush(1);
    forward_sockets($client, $server);

    $self->_clean_up();

    return 1;
} # end _forward

#----------------------------------------------------------------------
#** @method private _clean_up ($self)
# @brief Clean forward connection from DB
# @return scalar True value in success
#*
sub _clean_up {
    my ( $self ) = @_;

    if ( defined $self->middleware->{socket} ){
        close($self->middleware->{socket});
    }
    if ( defined $self->server->{socket} ){
        close($self->server->{socket});
    }

    $self->dbref->clean_connections($self->client);

    return 1;
} # end _clean_up

__PACKAGE__->meta->make_immutable;

1;