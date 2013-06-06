#!/usr/bin/perl

package SyncDiff::Util 0.01;
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
