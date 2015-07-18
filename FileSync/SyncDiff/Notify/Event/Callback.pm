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

package FileSync::SyncDiff::Notify::Event::Callback;
use Moose;

use MooseX::Types::Moose qw(CodeRef);

has 'callback' => (
    traits   => ['Code'],
    is       => 'ro',
    isa      => CodeRef,
    required => 1,
    handles  => {
        call_callback => 'execute',
    },
);

for my $event (qw/modify/){
    __PACKAGE__->meta->add_method( "handle_$event" => sub {
        my $self = shift;
        $self->call_callback($event, @_);
    });
}

with 'FileSync::SyncDiff::Notify::Event';

1;

__END__

=pod

=head1 NAME

FileSync::SyncDiff::Notify::Event::Callback - delegates everything to a coderef

=head2 callback

Coderef to be called when an event is received.

=head1 DESCRIPTION

This Event delegates every event to the C<callback> coderef.
The coderef gets the name of the event being delegated
(now only modify,but it could be expand on another events)
and the args that that event handler
would normally get.

=cut