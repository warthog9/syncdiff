####################################################################
#
#    This file was generated using Parse::Yapp version 1.05.
#
#        Don't edit this file, use source file instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
####################################################################

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

package FileSync::SyncDiff::ParseCfg;
use vars qw ( @ISA );
use strict;

@ISA= qw ( Parse::Yapp::Driver );
use Parse::Yapp::Driver;

#line 1 "psync_cfg_parser.y"
 # start of the code section

our $DEBUG = 0;

use Data::Dumper;
use Sys::Hostname;
use File::FnMatch qw(:fnmatch);    # import everything

my $autonum = 0;

my %groups;

my %prefixes;

my $curgroup = undef;

my $curprefix = undef;

my $ignore_uid = 0;
my $ignore_gid = 0;
my $ignore_mod = 0;

my $debug_mode = 0;

sub get_groups {
	return %groups;
}

sub get_prefixes {
	return %prefixes;
}

sub get_ignores {
	return ($ignore_uid, $ignore_gid, $ignore_mod);
}

sub get_debug {
	return $debug_mode;
}

sub new_group {
	my ($name) = @_;
#	print "function: new_group()\n";
#
#	print "\tnew_group - name: ". $name ."\n";

	if( $name eq "" ){
		$name = "group_". $autonum;
		$autonum++;
	}

	$curgroup = $name;

	$groups{$name} = {};
} # end new_group

sub add_host {
	my ($hostname) = @_;
	my $local_hostname = hostname;

#	print "function: add_host()\n";
#
#	print "\tadd_host: ". $hostname ."\n";

	$hostname = lc($hostname);
	$local_hostname = lc($local_hostname);

	if( $hostname eq $local_hostname){
		#print "\t~~ Found ourselves\n";
		return;
	} 

	if(
		$groups{$curgroup}->{'host'} == undef
		||
		$groups{$curgroup}->{'host'} eq ""
	){
		my @temparray = ();
		$groups{$curgroup}->{'host'} = \@temparray;
	}

#	print Dumper \@_;

	my @temparray = ( $hostname, );

#	print Dumper \@temparray;
#	print Dumper $groups{$curgroup}->{'host'};

	push( @{ $groups{$curgroup}->{'host'} }, $hostname);
} # end add_host

sub add_patt {
	my($flat, $pattern) = @_;

#	print "function: add_patt()\n";
#	print "\tadd_patt - pattern: ". $pattern ."\n";

	if(
		$groups{$curgroup}->{'patterns'} == undef
		||
		$groups{$curgroup}->{'patterns'} eq ""
	){
		my @temparray = ();
		$groups{$curgroup}->{'patterns'} = \@temparray;
	}
	
	push( @{ $groups{$curgroup}->{'patterns'} }, $pattern);
} # end add_patt

sub set_key {
	my( $key ) = @_;
#	print "function: set_key()\n";

	if( $groups{$curgroup}->{'key'} ne "" ){
		print "*** Multiple keys found for group '". $curgroup ."' - last one wins!  You are warned. ***\n";
	}

	if(
		$key =~ /^\//
		&& 
		-e $key
	){
		local $/;
		open(FILE, $key) or die "Can't read file '$key' [$!]\n";  
		$key = <FILE>; 
		close (FILE);  
	}

	print "Key is: $key\n";

	if( length($key) < 32 ){
		print "*** WARNING ***\n";
		print "\tKey for group:". $curgroup ." is less than 32 charaters.  Security is at risk\n";
		print "***************\n";
	}
	$groups{$curgroup}->{'key'} = $key;
} # end set_key()

sub set_auto {
	my ( $auto_resolve ) = @_;
#	print "function: set_auto()\n";

	$auto_resolve = lc( $auto_resolve );

	if( $auto_resolve eq "none" ){
		$groups{$curgroup}->{'auto_resolve'} = "none";
		return;
	}

	if( $auto_resolve eq "first" ){
		$groups{$curgroup}->{'auto_resolve'} = "first";
		return;
	}

	if( $auto_resolve eq "younger" ){
		$groups{$curgroup}->{'auto_resolve'} = "younger";
		return;
	}

	if( $auto_resolve eq "older" ){
		$groups{$curgroup}->{'auto_resolve'} = "older";
		return;
	}

	if( $auto_resolve eq "bigger" ){
		$groups{$curgroup}->{'auto_resolve'} = "bigger";
		return;
	}

	if( $auto_resolve eq "smaller" ){
		$groups{$curgroup}->{'auto_resolve'} = "smaller";
		return;
	}

	if( $auto_resolve eq "copy" ){
		$groups{$curgroup}->{'auto_resolve'} = "copy";
		return;
	}

	print "*** WARNING ***\n";
	print "\tUnknown auto resolution mechanism: ". $auto_resolve ."\n";
	print "\tIgnoring option\n";
	print "***************\n";
} # end set_auto()

sub set_bak_dir {
	my ($back_dir) = @_;
#	print "function: set_bak_dir()\n";

	$groups{$curgroup}->{'back_dir'} = $back_dir;
} # end set_bak_dir();

sub set_bak_gen {
	my ($backup_generations) = @_;
#	print "function: set_bak_gen()\n";

	if( $backup_generations =~ /[^0-9]+/ ){
		print "*** WARNING ***\n";
		print "\tUnknown number of Backup Generations:  ". $backup_generations ."\n";
		print "\tIgnoring option\n";
		print "***************\n";
		return;
	}

	$groups{$curgroup}->{'backup_generations'} = $backup_generations;
} # end set_back_gen()

sub check_group {
#	print "function: check_group()\n";

	if( length( $groups{$curgroup}->{'key'} ) <= 0 ){
		die("Config error: groups must have a key.\n");
	}
} # end check_group()

sub new_action {
	print "function: new_action()\n";
} # end new_action()

sub add_action_pattern {
	print "function: add_action_pattern()\n";
} # end add_action_pattern

sub add_action_exec {
	print "function: add_action_exec()\n";
} # end add_action_exec()

sub set_action_logfile {
	print "function: set_action_logfile()\n";
} # end set_action_logfile()

sub set_action_dolocal {
	print "function: set_action_dolocal()\n";
} # end set_action_dolocal

sub new_prefix {
	my( $pname ) = @_;

#	print "function: new_prefix: $pname\n";

	$curprefix = $pname;

	$prefixes{$pname} = "";
} # end new_prefix

sub new_prefix_entry {
	my( $pattern, $path ) = @_;
#	print "function: new_prefix_entry()\n";

	if( $path !~ /^\// ){
		print "\t Prefix Path: '". $path ."' is not an absolute path.\n";
	}

	my $hostname = hostname;

	if(
		fnmatch( $pattern, $hostname )
		&&
		(
			$prefixes{$curprefix} eq ""
			||
			$prefixes{$curprefix} eq undef
		)
	){
		$prefixes{$curprefix}=$path;
	}
} # end new_prefix_entry()

sub new_ignore {
	my( $propname ) = @_;
#	print "function: new_ignore()\n";

	if( $propname eq "uid" ){
		$ignore_uid = 1;
	} elsif( $propname eq "gid" ){
		$ignore_gid = 1;
	} elsif( $propname eq "mod" ){
		$ignore_mod = 1;
	} else {
		print "\tInvalid ignore option: '". $propname ."' - IGNORING\n";
	}
} # end new_ignore()

sub debug_mode {
	my ($debug) = @_;
	if ( $debug == 1 || $debug == 0 ) {
		$debug_mode = $debug // 0;
	}
	else {
		print "\tdebug option should be 0 or 1 - IGNORING\n";
	}
}# end debug_mode()

sub on_cygwin_lowercase {
	my( $string ) = @_;
#	print "function: on_cygwin_lowercase()\n";

	lc( $string );

#	print "on_cygwin_loewrcase: ". $string ."\n";

	return $string;
} # end on_cygwin_lowercase() 

sub disable_cygwin_lowercase_hack {
	print "function: disable_cygwin_lowercase_hack()\n";
}



sub new {
        my($class)=shift;
        ref($class)
    and $class=ref($class);

    my($self)=$class->SUPER::new( yyversion => '1.05',
                                  yystates =>
[
	{#State 0
		ACTIONS => {
			'TK_IGNORE' => 3,
			'TK_PREFIX' => 4,
			'TK_DEBUG' => 1,
			'TK_NOCYGLOWER' => 2,
			'TK_GROUP' => 8
		},
		DEFAULT => -1,
		GOTOS => {
			'block' => 6,
			'config' => 5,
			'block_header' => 7
		}
	},
	{#State 1
		ACTIONS => {
			'TK_STRING' => 9
		},
		DEFAULT => -11,
		GOTOS => {
			'debug' => 10
		}
	},
	{#State 2
		ACTIONS => {
			'TK_STEND' => 11
		}
	},
	{#State 3
		ACTIONS => {
			'TK_STRING' => 12
		},
		DEFAULT => -9,
		GOTOS => {
			'ignore_list' => 13
		}
	},
	{#State 4
		ACTIONS => {
			'TK_STRING' => 14
		}
	},
	{#State 5
		ACTIONS => {
			'' => 15
		}
	},
	{#State 6
		ACTIONS => {
			'TK_IGNORE' => 3,
			'TK_PREFIX' => 4,
			'TK_DEBUG' => 1,
			'TK_NOCYGLOWER' => 2,
			'TK_GROUP' => 8
		},
		DEFAULT => -1,
		GOTOS => {
			'config' => 16,
			'block' => 6,
			'block_header' => 7
		}
	},
	{#State 7
		ACTIONS => {
			'TK_BLOCK_BEGIN' => 18
		},
		GOTOS => {
			'block_body' => 17
		}
	},
	{#State 8
		ACTIONS => {
			'TK_STRING' => 19
		},
		DEFAULT => -15
	},
	{#State 9
		ACTIONS => {
			'TK_STRING' => 9
		},
		DEFAULT => -11,
		GOTOS => {
			'debug' => 20
		}
	},
	{#State 10
		ACTIONS => {
			'TK_STEND' => 21
		}
	},
	{#State 11
		DEFAULT => -8
	},
	{#State 12
		ACTIONS => {
			'TK_STRING' => 12
		},
		DEFAULT => -9,
		GOTOS => {
			'ignore_list' => 22
		}
	},
	{#State 13
		ACTIONS => {
			'TK_STEND' => 23
		}
	},
	{#State 14
		DEFAULT => -4,
		GOTOS => {
			'@1-2' => 24
		}
	},
	{#State 15
		DEFAULT => 0
	},
	{#State 16
		DEFAULT => -2
	},
	{#State 17
		DEFAULT => -3
	},
	{#State 18
		ACTIONS => {
			'TK_EXCL' => 25,
			'TK_KEY' => 26,
			'TK_ACTION' => 28,
			'TK_BAK_GEN' => 29,
			'TK_INCL' => 31,
			'TK_BAK_DIR' => 32,
			'TK_AUTO' => 33,
			'TK_HOST' => 36,
			'TK_COMP' => 35
		},
		DEFAULT => -18,
		GOTOS => {
			'stmt' => 30,
			'stmts' => 27,
			'action' => 34
		}
	},
	{#State 19
		DEFAULT => -16
	},
	{#State 20
		DEFAULT => -12
	},
	{#State 21
		DEFAULT => -7
	},
	{#State 22
		DEFAULT => -10
	},
	{#State 23
		DEFAULT => -6
	},
	{#State 24
		ACTIONS => {
			'TK_BLOCK_BEGIN' => 37
		}
	},
	{#State 25
		DEFAULT => -36,
		GOTOS => {
			'excl_list' => 38
		}
	},
	{#State 26
		ACTIONS => {
			'TK_STRING' => 39
		}
	},
	{#State 27
		ACTIONS => {
			'TK_BLOCK_END' => 40
		}
	},
	{#State 28
		DEFAULT => -42,
		GOTOS => {
			'@2-1' => 41
		}
	},
	{#State 29
		ACTIONS => {
			'TK_STRING' => 42
		}
	},
	{#State 30
		ACTIONS => {
			'TK_STEND' => 43
		}
	},
	{#State 31
		DEFAULT => -38,
		GOTOS => {
			'incl_list' => 44
		}
	},
	{#State 32
		ACTIONS => {
			'TK_STRING' => 45
		}
	},
	{#State 33
		ACTIONS => {
			'TK_STRING' => 46
		}
	},
	{#State 34
		ACTIONS => {
			'TK_EXCL' => 25,
			'TK_KEY' => 26,
			'TK_ACTION' => 28,
			'TK_BAK_GEN' => 29,
			'TK_INCL' => 31,
			'TK_BAK_DIR' => 32,
			'TK_AUTO' => 33,
			'TK_HOST' => 36,
			'TK_COMP' => 35
		},
		DEFAULT => -18,
		GOTOS => {
			'stmt' => 30,
			'stmts' => 47,
			'action' => 34
		}
	},
	{#State 35
		ACTIONS => {
			'TK_STEND' => -40
		},
		DEFAULT => -38,
		GOTOS => {
			'comp_list' => 49,
			'incl_list' => 48
		}
	},
	{#State 36
		DEFAULT => -29,
		GOTOS => {
			'host_list' => 50
		}
	},
	{#State 37
		DEFAULT => -13,
		GOTOS => {
			'prefix_list' => 51
		}
	},
	{#State 38
		ACTIONS => {
			'TK_STRING' => 52
		},
		DEFAULT => -22
	},
	{#State 39
		DEFAULT => -25
	},
	{#State 40
		DEFAULT => -17
	},
	{#State 41
		ACTIONS => {
			'TK_BLOCK_BEGIN' => 53
		}
	},
	{#State 42
		DEFAULT => -28
	},
	{#State 43
		ACTIONS => {
			'TK_EXCL' => 25,
			'TK_KEY' => 26,
			'TK_ACTION' => 28,
			'TK_BAK_GEN' => 29,
			'TK_INCL' => 31,
			'TK_BAK_DIR' => 32,
			'TK_AUTO' => 33,
			'TK_HOST' => 36,
			'TK_COMP' => 35
		},
		DEFAULT => -18,
		GOTOS => {
			'stmt' => 30,
			'stmts' => 54,
			'action' => 34
		}
	},
	{#State 44
		ACTIONS => {
			'TK_STRING' => 55
		},
		DEFAULT => -23
	},
	{#State 45
		DEFAULT => -27
	},
	{#State 46
		DEFAULT => -26
	},
	{#State 47
		DEFAULT => -20
	},
	{#State 48
		ACTIONS => {
			'TK_STRING' => 56
		}
	},
	{#State 49
		DEFAULT => -24
	},
	{#State 50
		ACTIONS => {
			'TK_STRING' => 58,
			'TK_POPEN' => 57
		},
		DEFAULT => -21
	},
	{#State 51
		ACTIONS => {
			'TK_BLOCK_END' => 59,
			'TK_ON' => 60
		}
	},
	{#State 52
		DEFAULT => -37
	},
	{#State 53
		ACTIONS => {
			'TK_EXEC' => 66,
			'TK_LOGFILE' => 63,
			'TK_PATTERN' => 65,
			'TK_DOLOCAL' => 64
		},
		DEFAULT => -44,
		GOTOS => {
			'action_stmt' => 61,
			'action_stmts' => 62
		}
	},
	{#State 54
		DEFAULT => -19
	},
	{#State 55
		DEFAULT => -39
	},
	{#State 56
		ACTIONS => {
			'TK_STEND' => -41
		},
		DEFAULT => -39
	},
	{#State 57
		DEFAULT => -33,
		GOTOS => {
			'host_list_slaves' => 67
		}
	},
	{#State 58
		ACTIONS => {
			'TK_AT' => 68
		},
		DEFAULT => -30
	},
	{#State 59
		DEFAULT => -5
	},
	{#State 60
		ACTIONS => {
			'TK_STRING' => 69
		}
	},
	{#State 61
		ACTIONS => {
			'TK_STEND' => 70
		}
	},
	{#State 62
		ACTIONS => {
			'TK_BLOCK_END' => 71
		}
	},
	{#State 63
		ACTIONS => {
			'TK_STRING' => 72
		}
	},
	{#State 64
		DEFAULT => -49
	},
	{#State 65
		DEFAULT => -50,
		GOTOS => {
			'action_pattern_list' => 73
		}
	},
	{#State 66
		DEFAULT => -52,
		GOTOS => {
			'action_exec_list' => 74
		}
	},
	{#State 67
		ACTIONS => {
			'TK_PCLOSE' => 75,
			'TK_STRING' => 76
		}
	},
	{#State 68
		ACTIONS => {
			'TK_STRING' => 77
		}
	},
	{#State 69
		ACTIONS => {
			'TK_COLON' => 78
		}
	},
	{#State 70
		ACTIONS => {
			'TK_EXEC' => 66,
			'TK_LOGFILE' => 63,
			'TK_PATTERN' => 65,
			'TK_DOLOCAL' => 64
		},
		DEFAULT => -44,
		GOTOS => {
			'action_stmt' => 61,
			'action_stmts' => 79
		}
	},
	{#State 71
		DEFAULT => -43
	},
	{#State 72
		DEFAULT => -48
	},
	{#State 73
		ACTIONS => {
			'TK_STRING' => 80
		},
		DEFAULT => -46
	},
	{#State 74
		ACTIONS => {
			'TK_STRING' => 81
		},
		DEFAULT => -47
	},
	{#State 75
		DEFAULT => -29,
		GOTOS => {
			'host_list' => 82
		}
	},
	{#State 76
		ACTIONS => {
			'TK_AT' => 83
		},
		DEFAULT => -34
	},
	{#State 77
		DEFAULT => -31
	},
	{#State 78
		ACTIONS => {
			'TK_STRING' => 84
		}
	},
	{#State 79
		DEFAULT => -45
	},
	{#State 80
		DEFAULT => -51
	},
	{#State 81
		DEFAULT => -53
	},
	{#State 82
		ACTIONS => {
			'TK_STRING' => 58,
			'TK_POPEN' => 57
		},
		DEFAULT => -32
	},
	{#State 83
		ACTIONS => {
			'TK_STRING' => 85
		}
	},
	{#State 84
		ACTIONS => {
			'TK_STEND' => 86
		}
	},
	{#State 85
		DEFAULT => -35
	},
	{#State 86
		DEFAULT => -14
	}
],
                                  yyrules  =>
[
	[#Rule 0
		 '$start', 2, undef
	],
	[#Rule 1
		 'config', 0, undef
	],
	[#Rule 2
		 'config', 2, undef
	],
	[#Rule 3
		 'block', 2, undef
	],
	[#Rule 4
		 '@1-2', 0,
sub
#line 360 "syncdiff_cfg_parser.y"
{ new_prefix($_[2]); }
	],
	[#Rule 5
		 'block', 6,
sub
#line 362 "syncdiff_cfg_parser.y"
{ }
	],
	[#Rule 6
		 'block', 3, undef
	],
	[#Rule 7
		 'block', 3, undef
	],
	[#Rule 8
		 'block', 2,
sub
#line 366 "syncdiff_cfg_parser.y"
{ disable_cygwin_lowercase_hack(); }
	],
	[#Rule 9
		 'ignore_list', 0, undef
	],
	[#Rule 10
		 'ignore_list', 2,
sub
#line 372 "syncdiff_cfg_parser.y"
{ new_ignore($_[1]); }
	],
	[#Rule 11
		 'debug', 0, undef
	],
	[#Rule 12
		 'debug', 2,
sub
#line 378 "syncdiff_cfg_parser.y"
{ debug_mode($_[1]); }
	],
	[#Rule 13
		 'prefix_list', 0, undef
	],
	[#Rule 14
		 'prefix_list', 6,
sub
#line 384 "syncdiff_cfg_parser.y"
{ new_prefix_entry($_[3], on_cygwin_lowercase($_[5])); }
	],
	[#Rule 15
		 'block_header', 1,
sub
#line 389 "syncdiff_cfg_parser.y"
{ new_group(0);  }
	],
	[#Rule 16
		 'block_header', 2,
sub
#line 391 "syncdiff_cfg_parser.y"
{ new_group($_[2]); }
	],
	[#Rule 17
		 'block_body', 3,
sub
#line 396 "syncdiff_cfg_parser.y"
{ check_group(); }
	],
	[#Rule 18
		 'stmts', 0, undef
	],
	[#Rule 19
		 'stmts', 3, undef
	],
	[#Rule 20
		 'stmts', 2, undef
	],
	[#Rule 21
		 'stmt', 2, undef
	],
	[#Rule 22
		 'stmt', 2, undef
	],
	[#Rule 23
		 'stmt', 2, undef
	],
	[#Rule 24
		 'stmt', 2, undef
	],
	[#Rule 25
		 'stmt', 2,
sub
#line 411 "syncdiff_cfg_parser.y"
{ set_key($_[2]); }
	],
	[#Rule 26
		 'stmt', 2,
sub
#line 413 "syncdiff_cfg_parser.y"
{ set_auto($_[2]); }
	],
	[#Rule 27
		 'stmt', 2,
sub
#line 415 "syncdiff_cfg_parser.y"
{ set_bak_dir($_[2]); }
	],
	[#Rule 28
		 'stmt', 2,
sub
#line 417 "syncdiff_cfg_parser.y"
{ set_bak_gen($_[2]); }
	],
	[#Rule 29
		 'host_list', 0, undef
	],
	[#Rule 30
		 'host_list', 2,
sub
#line 423 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[2], 0); }
	],
	[#Rule 31
		 'host_list', 4,
sub
#line 425 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[4], 0); }
	],
	[#Rule 32
		 'host_list', 5, undef
	],
	[#Rule 33
		 'host_list_slaves', 0, undef
	],
	[#Rule 34
		 'host_list_slaves', 2,
sub
#line 432 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[2], 1); }
	],
	[#Rule 35
		 'host_list_slaves', 4,
sub
#line 434 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[4], 1); }
	],
	[#Rule 36
		 'excl_list', 0, undef
	],
	[#Rule 37
		 'excl_list', 2,
sub
#line 440 "syncdiff_cfg_parser.y"
{ add_patt(0, on_cygwin_lowercase($_[2])); }
	],
	[#Rule 38
		 'incl_list', 0, undef
	],
	[#Rule 39
		 'incl_list', 2,
sub
#line 446 "syncdiff_cfg_parser.y"
{ add_patt(1, on_cygwin_lowercase($_[2])); }
	],
	[#Rule 40
		 'comp_list', 0, undef
	],
	[#Rule 41
		 'comp_list', 2,
sub
#line 452 "syncdiff_cfg_parser.y"
{ add_patt(2, on_cygwin_lowercase($_[2])); }
	],
	[#Rule 42
		 '@2-1', 0,
sub
#line 457 "syncdiff_cfg_parser.y"
{ new_action(); }
	],
	[#Rule 43
		 'action', 5, undef
	],
	[#Rule 44
		 'action_stmts', 0, undef
	],
	[#Rule 45
		 'action_stmts', 3, undef
	],
	[#Rule 46
		 'action_stmt', 2, undef
	],
	[#Rule 47
		 'action_stmt', 2, undef
	],
	[#Rule 48
		 'action_stmt', 2,
sub
#line 471 "syncdiff_cfg_parser.y"
{ set_action_logfile($_[2]); }
	],
	[#Rule 49
		 'action_stmt', 1,
sub
#line 473 "syncdiff_cfg_parser.y"
{ set_action_dolocal(); }
	],
	[#Rule 50
		 'action_pattern_list', 0, undef
	],
	[#Rule 51
		 'action_pattern_list', 2,
sub
#line 479 "syncdiff_cfg_parser.y"
{ add_action_pattern(on_cygwin_lowercase($_[2])); }
	],
	[#Rule 52
		 'action_exec_list', 0, undef
	],
	[#Rule 53
		 'action_exec_list', 2,
sub
#line 485 "syncdiff_cfg_parser.y"
{ add_action_exec($_[2]); }
	]
],
                                  @_);
    bless($self,$class);
}

#line 488 "syncdiff_cfg_parser.y"



1;
