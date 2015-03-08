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

package FileSync::SyncDiff::Util;
$FileSync::SyncDiff::Util::VERSION = '0.01';
require Exporter;

@ISA = qw(Exporter);
@EXPORT_OK = qw(munge frobnicate);  # symbols to export on request
@EXPORT = qw(mitm_callback);

#
# Needed for dealing with DB stuff
#

#
# Debugging
#

our $DEBUG = 0;

use Data::Dumper;

# End includes

#
# moose variables
#

# End variables

sub mitm_callback {
	my ( $coderef, @args ) = @_;
	sub { $coderef->( ( @args, @_ ) ) }
}

1;
