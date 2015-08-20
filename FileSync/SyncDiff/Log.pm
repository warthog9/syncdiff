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
            format   => qq{%d [%p] %m{chomp} %n}
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
    required => 0,
);

has '_logger' => (
    is       => 'ro',
    init_arg => undef,
    isa      => 'HashRef',
    builder  => '_build_logger'
);

sub _build_logger {
    my ($self) = @_;

    my $log_info = {};
    for my $level ( ($INFO, $DEBUG, $WARN, $ERROR, $FATAL) ) {
        my $format   = &LOG_LEVEL_MAP->{$level}{format};
        my $appender = &LOG_LEVEL_MAP->{$level}{appender};
        my $layout   = Log::Log4perl::Layout::PatternLayout->new( $format );

        $appender->layout($layout);
        $log_info->{$level}{logger} = get_logger( __PACKAGE__ . $level );

        ($log_info->{$level}{logger})->additivity(0);
        ($log_info->{$level}{logger})->add_appender($appender);
        ($log_info->{$level}{logger})->level($level);
    }

    return $log_info;
}

sub _log {
    my ($self, $level) = @_;

    return $self->_logger->{$level}{logger};
}

#----------------------------------------------------------------------
#** @method private _compose_msg ($self, $format, @values)
# @brief Compose message from format and values.
# Messages should be in sprintf format or
# as a simple text
# @param $format - sprintf format message
# @param @values - values for formatting message
# @return scalar Message
#*
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

#----------------------------------------------------------------------
#** @method public debug ($self, $format, @values)
# @brief Print message with DEBUG level.
# @param $format - sprintf format message
# @param @values - values for formatting message
# @return scalar Message
#*
sub debug {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_log($DEBUG)->debug($msg);

    return $msg;
}

#----------------------------------------------------------------------
#** @method public info ($self, $format, @values)
# @brief Print message with INFO level.
# @param $format - sprintf format message
# @param @values - values for formatting message
# @return scalar Message
#*
sub info {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_log($INFO)->info($msg);

    return $msg;
}

#----------------------------------------------------------------------
#** @method public warn ($self, $format, @values)
# @brief Print message with WARN level.
# @param $format - sprintf format message
# @param @values - values for formatting message
# @return scalar Message
#*
sub warn {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_log($WARN)->logcarp($msg);

    return $msg;
}

#----------------------------------------------------------------------
#** @method public error ($self, $format, @values)
# @brief Print message with ERROR level.
# @param $format - sprintf format message
# @param @values - values for formatting message
# @return scalar Message
#*
sub error {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_log($ERROR)->error_warn($msg);

    return $msg;
}

#----------------------------------------------------------------------
#** @method public fatal ($self, $format, @values)
# @brief Print message with FATAL level.
# @param $format - sprintf format message
# @param @values - values for formatting message
# @return scalar Message
#*
sub fatal {
    my ( $self, $format, @values ) = @_;
    my $msg = $self->_compose_msg($format, @values);

    $self->_log($FATAL)->logcroak($msg);

    return $msg;
}

__PACKAGE__->meta->make_immutable;

1;
