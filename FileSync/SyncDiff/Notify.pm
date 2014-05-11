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

package FileSync::SyncDiff::Notify;
$FileSync::SyncDiff::Notify::VERSION = '0.01';

use Moose;

extends qw(FileSync::SyncDiff::Forkable);

use Carp;
use FileSync::SyncDiff::Notify::Plugin::Inotify2;
use AnyEvent;
use Data::Dumper;

has 'config' => (
		is	=> 'rw',
		isa	=> 'HashRef',
		required => 1,
);

sub _load_plugin {
    my $self = shift;

    if ( $^O eq 'linux' ) {
    	$self->_load_linux();
    }

    return 1;
}

sub run {
	my $self = shift;

	$self->fork();
}

sub _load_linux{
	my $self = shift;

	my @dirs;
	for my $group_data ( values %{$self->config->{groups}} ){
		push(@dirs, $group_data->{patterns});
	}

	my $cv = AnyEvent->condvar;

        my $inotify = FileSync::SyncDiff::Notify::Plugin::Inotify2->new(
        	dirs => @dirs,
	        event_receiver => sub {
	           my ($event, $file) = @_;
	           if($event eq 'modify') {
	           		print "modify file $file!\n";
	           }
	        },
		);

	$cv->recv;
}

override 'run_child' => sub {
	my( $self ) = @_;

	print "Run child on Notify";

	$self->_load_plugin();
};

__PACKAGE__->meta->make_immutable;