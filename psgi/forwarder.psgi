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

use Plack::Request;
use Data::Dumper;
use JSON::XS;

use FileSync::SyncDiff::Forwarder;

my $app = sub {
    my $env = shift;

    my $req = Plack::Request->new($env);
    my ( $key, $dir, $host) = ( undef, undef, undef );

    if ( $req->method eq 'POST' ) {
        #CGI compatible
        ( $key, $dir, $host ) = ( $req->param('key'), $req->param('include'), $req->param('host') );

        my $forwarder = FileSync::SyncDiff::Forwarder->new(
            client => { host => $host, auth_key => $key, dir => $dir },
        );
        $forwarder->run();
        my $body = encode_json({
            host => $forwarder->middleware->{host},
            port => $forwarder->middleware->{port},
        });
        return [ 200, ['Content-Type', 'application/json'], [ $body ] ];
    }

    return [ 200, ['Content-Type', 'text/html'], [] ];
};