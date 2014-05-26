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
use File::Pid;

use Data::Dumper;

use constant PID_FILE => './notify.pid';

has 'config_options' => (
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

sub _load_linux {
	my $self = shift;

	my @dirs;
	for my $group_data ( values %{$self->config_options->{groups}} ){
		push(@dirs, $group_data->{patterns});
	}

	my $cv = AnyEvent->condvar;

        my $inotify = FileSync::SyncDiff::Notify::Plugin::Inotify2->new(
        	dirs => @dirs,
	        event_receiver => sub {
	           my ($event, $file) = @_;
	           if($event eq 'modify') {
	           		for my $group ( keys %{$self->config_options->{groups}} ){
		           		for my $host ( @{ $self->config_options->{groups}->{ $group }->{host} } ){
							my $sock = new IO::Socket::INET (
											PeerAddr => $host,
											PeerPort => '7070',
											Proto => 'tcp',
											);
							if( ! $sock ){
								print "Could not create socket: $!\n";
								next;
							} # end skipping if the socket is broken

							$sock->autoflush(1);

							print $sock "$file IS MODIFY";

							close $sock;
		           		}
		           	}
	           }
	        },
		);

	$cv->recv;
}

override 'run_child' => sub {
	my( $self ) = @_;

	my $pid_obj = File::Pid->new({
    	file => PID_FILE
  	});

	if( my $pid = $pid_obj->running ){
		warn "Notifier is already running on $pid pid!";
		exit(0);
	}
	$pid_obj->write or die("Can't write $!");

	$self->_load_plugin();
};

__PACKAGE__->meta->make_immutable;