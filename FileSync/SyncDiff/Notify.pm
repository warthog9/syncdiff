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

use FileSync::SyncDiff::Scanner;
use FileSync::SyncDiff::Config;

use Carp qw(cluck confess carp);
use AnyEvent;
use File::Pid qw();
use JSON::XS qw(encode_json);
use Net::Address::IP::Local;
use File::Spec::Functions qw(catfile);
use IPC::ShareLite qw();
use Net::Ping qw();

use sigtrap 'handler' => \&_kill_handler, 'HUP', 'INT','ABRT','QUIT','TERM';

use Data::Dumper;

use constant PID_FILE => 'notify.pid';
use constant PID_DIR  => './';

has 'config' => (
        is  => 'rw',
        isa => 'FileSync::SyncDiff::Config',
        required => 1,
        );

has 'dbref' => (
        is  => 'rw',
        isa => 'Object',
        required => 1,
        );

sub _load_plugin {
    my $self = shift;

    if ( $^O =~ /linux/i ) {
        require FileSync::SyncDiff::Notify::Plugin::Inotify2;
        $self->_load_linux();
    }
    elsif ( $^O =~ /bsd/i || $^O =~ /darwin/i ) {
        require FileSync::SyncDiff::Notify::Plugin::KQueue;
        $self->_load_bsd();
    }
    else {
        confess "$^O is not supported!";
    }

    return 1;
}

sub run {
    my $self = shift;

    $self->start();

    if ( my $pid =  $self->is_alive() ){
        print "Notifier is already running with $pid pid!";
        return;
    }

    $self->fork();
}

sub stop {
    my $self = shift;

    my $is_running = 0;
    my $share;
    eval {
        $share = IPC::ShareLite->new(
            -key     => 'key',
            -create  => 'no',
            -destroy => 'no'
        );
    } || return;

    $share->store( $is_running );

    return $is_running;
}

sub start {
    my $self = shift;

    my $is_running = 1;
    my $share = IPC::ShareLite->new(
        -key     => 'key',
        -create  => 'yes',
        -destroy => 'no'
    ) || confess $!;

    $share->store( $is_running );

    return $is_running;
}

sub is_running {
    my $share;
    eval {
        $share = IPC::ShareLite->new(
            -key     => 'key',
            -create  => 'no',
            -destroy => 'no'
        );
    } || return;

    return $share->fetch();
}

sub is_alive {
    my $self = shift;

    my $pid_obj = File::Pid->new({
        file => catfile(PID_DIR, PID_FILE)
    });

    return $pid_obj->_get_pid_from_file();
}

sub _load_linux {
    my $self = shift;

    my @dirs;
    for my $group_data ( values %{$self->config->config->{groups}} ){
        push(@dirs, $group_data->{patterns});
    }

    my $cv = AnyEvent->condvar;

        my $inotify = FileSync::SyncDiff::Notify::Plugin::Inotify2->new(
            dirs => @dirs,
            event_receiver => sub {
                $self->_process_events(@_);
            }
        );

    $cv->recv;
}

sub _load_bsd {
    my $self = shift;

    my @dirs;
    for my $group_data ( values %{$self->config->config->{groups}} ){
        push(@dirs, $group_data->{patterns});
    }

    my $cv = AnyEvent->condvar;

        my $kqueue = FileSync::SyncDiff::Notify::Plugin::KQueue->new(
            includes => @dirs,
            event_receiver => sub {
                $self->_process_events(@_);
            }
        );

    $cv->recv;
}

sub _process_events {
    my ($self, $event, $file, $groupbase) = @_;
    if($event eq 'modify') {
        # Notify daemon was stopped
        return if ( ! $self->is_running() );

        print Dumper $event;

        while ( my($group_name, $group_data) = each(%{$self->config->config->{groups}}) ) {

            # Need to notify only those groups which contain a true include
            # for file which was modified
            next if( ! grep{ $_ eq $groupbase }@{ $group_data->{patterns} } );

            NEXT_HOST:
            for my $host ( @{ $group_data->{host} } ){
                my $p = Net::Ping->new();
                if ( ! $p->ping($host) ){
                    carp "$host is not alive!\n";
                    next NEXT_HOST;
                }
                $p->close();

                my $sock = new IO::Socket::INET (
                                PeerAddr => $host,
                                PeerPort => '7070',
                                Proto => 'tcp',
                                );
                if( ! $sock ){
                    cluck "Could not create socket: $!\n";
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
}

sub _kill_handler {
    my $pid_obj = File::Pid->new({
        file => catfile(PID_DIR, PID_FILE)
    });
    $pid_obj->remove;
    exit(1);
}

sub _daemonize {
    my $self = shift;
    my $pid_obj = File::Pid->new({
        file => catfile(PID_DIR, PID_FILE)
    });

    if( my $pid = $pid_obj->_get_pid_from_file() ){
        print "Notifier is already running with $pid pid!";
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