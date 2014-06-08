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

use Carp qw(cluck confess);
use FileSync::SyncDiff::Notify::Plugin::Inotify2;
use AnyEvent;
use File::Pid;
use JSON::XS qw/encode_json/;
use Net::Address::IP::Local;
use sigtrap 'handler' => \&_kill_handler, 'HUP', 'INT','ABRT','QUIT','TERM';

use Data::Dumper;

use constant PID_FILE => './notify.pid';

has 'config_options' => (
        is  => 'rw',
        isa => 'HashRef',
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

sub stop {
    my $self = shift;

    kill 'STOP', $self->pid;
}

sub start {
    my $self = shift;

    kill 'CONT', $self->pid;
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
               my ($event, $file, $config_include) = @_;
               if($event eq 'modify') {
                    while ( my($group_name, $group_data) = each(%{$self->config_options->{groups}}) ) {

                        # Need to notify only those groups which contain a true include
                        # for file which was modified
                        next if( ! grep{ $_ eq $config_include }@{ $group_data->{patterns} } );

                        for my $host ( @{ $group_data->{host} } ){
                            my $sock = new IO::Socket::INET (
                                            PeerAddr => $host,
                                            PeerPort => '7070',
                                            Proto => 'tcp',
                                            );
                            if( ! $sock ){
                                confess "Could not create socket: $!\n";
                                next;
                            } # end skipping if the socket is broken

                            $sock->autoflush(1);

                            my %request = (
                                'operation' => 'request_notify',
                                'hostname'  => Net::Address::IP::Local->public,
                                'group'     => $group_name,
                            );
                            my $json = encode_json(\%request);
                            print $sock $json;

                            close $sock;
                        }
                    }
               }
            },
        );

    $cv->recv;
}

sub _kill_handler {
    my $pid_obj = File::Pid->new({
        file => PID_FILE
    });
    $pid_obj->remove;
    exit(1);
}

sub _daemonize {
    my $self = shift;
    my $pid_obj = File::Pid->new({
        file => PID_FILE
    });

    if( my $pid = $pid_obj->running ){
        cluck "Notifier is already running with $pid pid!";
        exit(0);
    }
    $pid_obj->write || confess("Can't write $!");

    return $pid_obj->pid;
}

override 'run_child' => sub {
    my( $self ) = @_;

    $self->_daemonize();

    $self->_load_plugin();
};

__PACKAGE__->meta->make_immutable;