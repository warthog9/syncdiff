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

package FileSync::SyncDiff::Log;
$FileSync::SyncDiff::Log::VERSION = '0.01';

use Moose;
use Log::Log4perl qw(get_logger :levels);
use Log::Log4perl::Appender;
use Log::Log4perl::Layout::PatternLayout;

use Data::Dumper;

use constant {
    LOG_LEVEL_MAP => {
        $INFO   => {
            appender => Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::Screen",
                stderr => 1,
                utf8   => 1,
            ),
            format   => qq{%d [%p] %m{chomp} %n}
        },
        $DEBUG  => {
            appender => Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::File",
                filename => "/var/log/syncdiff.log",
                mode     => "append",
                utf8     => 1,
            ),
            format   => qq{%d [%p] %m{chomp} %T %n}
        },
        $WARN   => {
            appender => Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::File",
                filename => "/var/log/syncdiff.log",
                mode     => "append",
                utf8     => 1,
            ),
            format   => qq{%d [%p] %m{chomp} %T %n}
        },
        $ERROR  => {
            appender => Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::File",
                filename => "/var/log/syncdiff.log",
                mode     => "append",
                utf8     => 1,
            ),
            format   => qq{%d [%p] %m{chomp} %T %n}
        },
        $FATAL  => {
            appender => Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::File",
                filename => "/var/log/syncdiff.log",
                mode     => "append",
                utf8     => 1,
            ),
            format   => qq{%d [%p] %m{chomp} %T %n}
        },
    },
};

has 'config' => (
    is       => 'rw',
    isa      => 'FileSync::SyncDiff::Config',
    required => 1,
);

has '_logger' => (
    is       => 'ro',
    init_arg => undef,
    isa      => 'Log::Log4perl::Logger',
    default  => sub {
        return get_logger(__PACKAGE__);
    }
);

sub _init_logger {
    my ( $self, $level ) = @_;

    my $format   = &LOG_LEVEL_MAP->{$level}{format};
    my $appender = &LOG_LEVEL_MAP->{$level}{appender};

    my $layout = Log::Log4perl::Layout::PatternLayout->new( $format );
    $appender->layout($layout);

    $self->_logger->additivity(0);
    $self->_logger->add_appender($appender);
    $self->_logger->level($level);

    return $format;
}
# Messages could be in sprintf format or
# as simple text
sub _compose_msg {
    my ( $self, $format, @values ) = @_;
    my $msg = '';
    if ( scalar @values > 0 ) {
        $msg = sprintf( $format, map { defined $_ ? $_ : '' }@values );
    }
    else {
        $msg = $format;
    }

    return $msg;
}

sub debug {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_logger->reset;
    $self->_init_logger($DEBUG);
    $self->_logger->debug($msg);

    return $msg;
}

sub info {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_logger->reset;
    $self->_init_logger($INFO);
    $self->_logger->info($msg);

    return $msg;
}

sub warn {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_logger->reset;
    $self->_init_logger($WARN);
    $self->_logger->logcluck($msg);

    return $msg;
}

sub error {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_logger->reset;
    $self->_init_logger($ERROR);
    $self->_logger->logcroak($msg);

    return $msg;
}

sub fatal {
    my ( $self, $format, @values ) = @_;
   my $msg = $self->_compose_msg($format, @values);

    $self->_logger->reset;
    $self->_init_logger($FATAL);
    $self->_logger->logconfess($msg);

    return $msg;
}

__PACKAGE__->meta->make_immutable;

1;
