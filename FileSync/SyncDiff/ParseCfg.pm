####################################################################
#
#    This file was generated using Parse::Yapp version 1.05.
#
#        Don't edit this file, use source file instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
####################################################################
package FileSync::SyncDiff::ParseCfg;
use vars qw ( @ISA );
use strict;

@ISA= qw ( Parse::Yapp::Driver );
use Parse::Yapp::Driver;

#line 1 "syncdiff_cfg_parser.y"
 # start of the code section

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

use Data::Dumper;
use Sys::Hostname;
use File::FnMatch qw(:fnmatch);    # import everything
use URI;

use FileSync::SyncDiff::Log;

my $autonum = 0;

my %groups;

my %prefixes;

my $curgroup = undef;

my $curprefix = undef;

my $ignore_uid = 0;
my $ignore_gid = 0;
my $ignore_mod = 0;

my $log = FileSync::SyncDiff::Log->new();

sub get_groups {
	return %groups;
}

sub get_prefixes {
	return %prefixes;
}

sub get_ignores {
	return ($ignore_uid, $ignore_gid, $ignore_mod);
}

sub new_group {
	my ($name) = @_;

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

	$hostname = lc($hostname);
	$local_hostname = lc($local_hostname);

	if( $hostname eq $local_hostname){
		return;
	} 

	if( $groups{$curgroup}->{'host'} ){
		$groups{$curgroup}->{'host'} = \();
		return;
	}

	my $uri = URI->new($hostname);
	my ($host, $port) = (undef,undef);
	my $proto = eval { $uri->scheme() };
	if ($@) {
		$log->warn("Invalid protocol name");
	}

	if ( $proto ) {
		eval {
			$host = $uri->host();
			$port = $uri->port();
		};
		if ($@) {
			$log->warn("Invalid host format %s",$@);
			return;
		}
	}
	else {
		$host = $hostname;
		$port = 7070;
	}

	my @uri_info = ( {
		host  => $host,
		port  => $port,
		proto => $proto,
	} );

	push( @{ $groups{$curgroup}->{'host'} }, @uri_info);
} # end add_host

sub add_patt {
	my($flat, $pattern) = @_;

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

	if( $groups{$curgroup}->{'key'} ne "" ){
		$log->info("*** Multiple keys found for group %s - last one wins!  You are warned. ***", $curgroup);
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

	$log->debug("Key is: %s",$key);

	if( length($key) < 32 ){
		$log->warn("Key for group: %s is less than 32 charaters.  Security is at risk", $curgroup);
	}
	$groups{$curgroup}->{'key'} = $key;
} # end set_key()

sub set_auto {
	my ( $auto_resolve ) = @_;

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

	$log->warn("Unknown auto resolution mechanism: %s", $auto_resolve);
	$log->warn("Ignoring option");
} # end set_auto()

sub set_bak_dir {
	my ($back_dir) = @_;

	$groups{$curgroup}->{'back_dir'} = $back_dir;
} # end set_bak_dir();

sub set_bak_gen {
	my ($backup_generations) = @_;

	if( $backup_generations =~ /[^0-9]+/ ){
		$log->warn("Unknown number of Backup Generations: %s", $backup_generations);
		$log->warn("Ignoring option");
		return;
	}

	$groups{$curgroup}->{'backup_generations'} = $backup_generations;
} # end set_back_gen()

sub check_group {
	if( length( $groups{$curgroup}->{'key'} ) <= 0 ){
		$log->fatal("Config error: groups must have a key.");
	}
} # end check_group()

sub new_action {
	$log->debug("function: new_action()");
} # end new_action()

sub add_action_pattern {
	$log->debug("function: add_action_pattern()");
} # end add_action_pattern

sub add_action_exec {
	$log->debug("function: add_action_exec()");
} # end add_action_exec()

sub set_action_logfile {
	$log->debug("function: set_action_logfile()");
} # end set_action_logfile()

sub set_action_dolocal {
	$log->debug("function: set_action_dolocal()");
} # end set_action_dolocal

sub new_prefix {
	my( $pname ) = @_;

	$curprefix = $pname;

	$prefixes{$pname} = "";
} # end new_prefix

sub new_prefix_entry {
	my( $pattern, $path ) = @_;

	if( $path !~ /^\// ){
		$log->warn("Prefix Path: '%s' is not an absolute path", $path);
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

	if( $propname eq "uid" ){
		$ignore_uid = 1;
	} elsif( $propname eq "gid" ){
		$ignore_gid = 1;
	} elsif( $propname eq "mod" ){
		$ignore_mod = 1;
	} else {
		$log->warn("Invalid ignore option: '%s' - IGNORING", $propname);
	}
} # end new_ignore()

sub on_cygwin_lowercase {
	my( $string ) = @_;

	lc( $string );

	return $string;
} # end on_cygwin_lowercase() 

sub disable_cygwin_lowercase_hack {
	$log->debug("function: disable_cygwin_lowercase_hack()");
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
			'TK_IGNORE' => 1,
			'TK_PREFIX' => 2,
			'TK_NOCYGLOWER' => 3,
			'TK_GROUP' => 7
		},
		DEFAULT => -1,
		GOTOS => {
			'config' => 5,
			'block' => 4,
			'block_header' => 6
		}
	},
	{#State 1
		ACTIONS => {
			'TK_STRING' => 8
		},
		DEFAULT => -8,
		GOTOS => {
			'ignore_list' => 9
		}
	},
	{#State 2
		ACTIONS => {
			'TK_STRING' => 10
		}
	},
	{#State 3
		ACTIONS => {
			'TK_STEND' => 11
		}
	},
	{#State 4
		ACTIONS => {
			'TK_IGNORE' => 1,
			'TK_PREFIX' => 2,
			'TK_NOCYGLOWER' => 3,
			'TK_GROUP' => 7
		},
		DEFAULT => -1,
		GOTOS => {
			'config' => 12,
			'block' => 4,
			'block_header' => 6
		}
	},
	{#State 5
		ACTIONS => {
			'' => 13
		}
	},
	{#State 6
		ACTIONS => {
			'TK_BLOCK_BEGIN' => 15
		},
		GOTOS => {
			'block_body' => 14
		}
	},
	{#State 7
		ACTIONS => {
			'TK_STRING' => 16
		},
		DEFAULT => -12
	},
	{#State 8
		ACTIONS => {
			'TK_STRING' => 8
		},
		DEFAULT => -8,
		GOTOS => {
			'ignore_list' => 17
		}
	},
	{#State 9
		ACTIONS => {
			'TK_STEND' => 18
		}
	},
	{#State 10
		DEFAULT => -4,
		GOTOS => {
			'@1-2' => 19
		}
	},
	{#State 11
		DEFAULT => -7
	},
	{#State 12
		DEFAULT => -2
	},
	{#State 13
		DEFAULT => 0
	},
	{#State 14
		DEFAULT => -3
	},
	{#State 15
		ACTIONS => {
			'TK_EXCL' => 20,
			'TK_KEY' => 21,
			'TK_ACTION' => 23,
			'TK_BAK_GEN' => 24,
			'TK_INCL' => 26,
			'TK_BAK_DIR' => 27,
			'TK_AUTO' => 28,
			'TK_COMP' => 31,
			'TK_HOST' => 30
		},
		DEFAULT => -15,
		GOTOS => {
			'stmt' => 25,
			'stmts' => 22,
			'action' => 29
		}
	},
	{#State 16
		DEFAULT => -13
	},
	{#State 17
		DEFAULT => -9
	},
	{#State 18
		DEFAULT => -6
	},
	{#State 19
		ACTIONS => {
			'TK_BLOCK_BEGIN' => 32
		}
	},
	{#State 20
		DEFAULT => -33,
		GOTOS => {
			'excl_list' => 33
		}
	},
	{#State 21
		ACTIONS => {
			'TK_STRING' => 34
		}
	},
	{#State 22
		ACTIONS => {
			'TK_BLOCK_END' => 35
		}
	},
	{#State 23
		DEFAULT => -39,
		GOTOS => {
			'@2-1' => 36
		}
	},
	{#State 24
		ACTIONS => {
			'TK_STRING' => 37
		}
	},
	{#State 25
		ACTIONS => {
			'TK_STEND' => 38
		}
	},
	{#State 26
		DEFAULT => -35,
		GOTOS => {
			'incl_list' => 39
		}
	},
	{#State 27
		ACTIONS => {
			'TK_STRING' => 40
		}
	},
	{#State 28
		ACTIONS => {
			'TK_STRING' => 41
		}
	},
	{#State 29
		ACTIONS => {
			'TK_EXCL' => 20,
			'TK_KEY' => 21,
			'TK_ACTION' => 23,
			'TK_BAK_GEN' => 24,
			'TK_INCL' => 26,
			'TK_BAK_DIR' => 27,
			'TK_AUTO' => 28,
			'TK_HOST' => 30,
			'TK_COMP' => 31
		},
		DEFAULT => -15,
		GOTOS => {
			'stmt' => 25,
			'stmts' => 42,
			'action' => 29
		}
	},
	{#State 30
		DEFAULT => -26,
		GOTOS => {
			'host_list' => 43
		}
	},
	{#State 31
		ACTIONS => {
			'TK_STEND' => -37
		},
		DEFAULT => -35,
		GOTOS => {
			'comp_list' => 45,
			'incl_list' => 44
		}
	},
	{#State 32
		DEFAULT => -10,
		GOTOS => {
			'prefix_list' => 46
		}
	},
	{#State 33
		ACTIONS => {
			'TK_STRING' => 47
		},
		DEFAULT => -19
	},
	{#State 34
		DEFAULT => -22
	},
	{#State 35
		DEFAULT => -14
	},
	{#State 36
		ACTIONS => {
			'TK_BLOCK_BEGIN' => 48
		}
	},
	{#State 37
		DEFAULT => -25
	},
	{#State 38
		ACTIONS => {
			'TK_EXCL' => 20,
			'TK_KEY' => 21,
			'TK_ACTION' => 23,
			'TK_BAK_GEN' => 24,
			'TK_INCL' => 26,
			'TK_BAK_DIR' => 27,
			'TK_AUTO' => 28,
			'TK_HOST' => 30,
			'TK_COMP' => 31
		},
		DEFAULT => -15,
		GOTOS => {
			'stmt' => 25,
			'stmts' => 49,
			'action' => 29
		}
	},
	{#State 39
		ACTIONS => {
			'TK_STRING' => 50
		},
		DEFAULT => -20
	},
	{#State 40
		DEFAULT => -24
	},
	{#State 41
		DEFAULT => -23
	},
	{#State 42
		DEFAULT => -17
	},
	{#State 43
		ACTIONS => {
			'TK_STRING' => 52,
			'TK_POPEN' => 51
		},
		DEFAULT => -18
	},
	{#State 44
		ACTIONS => {
			'TK_STRING' => 53
		}
	},
	{#State 45
		DEFAULT => -21
	},
	{#State 46
		ACTIONS => {
			'TK_BLOCK_END' => 54,
			'TK_ON' => 55
		}
	},
	{#State 47
		DEFAULT => -34
	},
	{#State 48
		ACTIONS => {
			'TK_EXEC' => 61,
			'TK_LOGFILE' => 58,
			'TK_PATTERN' => 60,
			'TK_DOLOCAL' => 59
		},
		DEFAULT => -41,
		GOTOS => {
			'action_stmt' => 56,
			'action_stmts' => 57
		}
	},
	{#State 49
		DEFAULT => -16
	},
	{#State 50
		DEFAULT => -36
	},
	{#State 51
		DEFAULT => -30,
		GOTOS => {
			'host_list_slaves' => 62
		}
	},
	{#State 52
		ACTIONS => {
			'TK_AT' => 63
		},
		DEFAULT => -27
	},
	{#State 53
		ACTIONS => {
			'TK_STEND' => -38
		},
		DEFAULT => -36
	},
	{#State 54
		DEFAULT => -5
	},
	{#State 55
		ACTIONS => {
			'TK_STRING' => 64
		}
	},
	{#State 56
		ACTIONS => {
			'TK_STEND' => 65
		}
	},
	{#State 57
		ACTIONS => {
			'TK_BLOCK_END' => 66
		}
	},
	{#State 58
		ACTIONS => {
			'TK_STRING' => 67
		}
	},
	{#State 59
		DEFAULT => -46
	},
	{#State 60
		DEFAULT => -47,
		GOTOS => {
			'action_pattern_list' => 68
		}
	},
	{#State 61
		DEFAULT => -49,
		GOTOS => {
			'action_exec_list' => 69
		}
	},
	{#State 62
		ACTIONS => {
			'TK_PCLOSE' => 70,
			'TK_STRING' => 71
		}
	},
	{#State 63
		ACTIONS => {
			'TK_STRING' => 72
		}
	},
	{#State 64
		ACTIONS => {
			'TK_COLON' => 73
		}
	},
	{#State 65
		ACTIONS => {
			'TK_EXEC' => 61,
			'TK_LOGFILE' => 58,
			'TK_PATTERN' => 60,
			'TK_DOLOCAL' => 59
		},
		DEFAULT => -41,
		GOTOS => {
			'action_stmt' => 56,
			'action_stmts' => 74
		}
	},
	{#State 66
		DEFAULT => -40
	},
	{#State 67
		DEFAULT => -45
	},
	{#State 68
		ACTIONS => {
			'TK_STRING' => 75
		},
		DEFAULT => -43
	},
	{#State 69
		ACTIONS => {
			'TK_STRING' => 76
		},
		DEFAULT => -44
	},
	{#State 70
		DEFAULT => -26,
		GOTOS => {
			'host_list' => 77
		}
	},
	{#State 71
		ACTIONS => {
			'TK_AT' => 78
		},
		DEFAULT => -31
	},
	{#State 72
		DEFAULT => -28
	},
	{#State 73
		ACTIONS => {
			'TK_STRING' => 79
		}
	},
	{#State 74
		DEFAULT => -42
	},
	{#State 75
		DEFAULT => -48
	},
	{#State 76
		DEFAULT => -50
	},
	{#State 77
		ACTIONS => {
			'TK_STRING' => 52,
			'TK_POPEN' => 51
		},
		DEFAULT => -29
	},
	{#State 78
		ACTIONS => {
			'TK_STRING' => 80
		}
	},
	{#State 79
		ACTIONS => {
			'TK_STEND' => 81
		}
	},
	{#State 80
		DEFAULT => -32
	},
	{#State 81
		DEFAULT => -11
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
#line 336 "syncdiff_cfg_parser.y"
{ new_prefix($_[2]); }
	],
	[#Rule 5
		 'block', 6,
sub
#line 338 "syncdiff_cfg_parser.y"
{ }
	],
	[#Rule 6
		 'block', 3, undef
	],
	[#Rule 7
		 'block', 2,
sub
#line 341 "syncdiff_cfg_parser.y"
{ disable_cygwin_lowercase_hack(); }
	],
	[#Rule 8
		 'ignore_list', 0, undef
	],
	[#Rule 9
		 'ignore_list', 2,
sub
#line 347 "syncdiff_cfg_parser.y"
{ new_ignore($_[1]); }
	],
	[#Rule 10
		 'prefix_list', 0, undef
	],
	[#Rule 11
		 'prefix_list', 6,
sub
#line 353 "syncdiff_cfg_parser.y"
{ new_prefix_entry($_[3], on_cygwin_lowercase($_[5])); }
	],
	[#Rule 12
		 'block_header', 1,
sub
#line 358 "syncdiff_cfg_parser.y"
{ new_group(0);  }
	],
	[#Rule 13
		 'block_header', 2,
sub
#line 360 "syncdiff_cfg_parser.y"
{ new_group($_[2]); }
	],
	[#Rule 14
		 'block_body', 3,
sub
#line 365 "syncdiff_cfg_parser.y"
{ check_group(); }
	],
	[#Rule 15
		 'stmts', 0, undef
	],
	[#Rule 16
		 'stmts', 3, undef
	],
	[#Rule 17
		 'stmts', 2, undef
	],
	[#Rule 18
		 'stmt', 2, undef
	],
	[#Rule 19
		 'stmt', 2, undef
	],
	[#Rule 20
		 'stmt', 2, undef
	],
	[#Rule 21
		 'stmt', 2, undef
	],
	[#Rule 22
		 'stmt', 2,
sub
#line 380 "syncdiff_cfg_parser.y"
{ set_key($_[2]); }
	],
	[#Rule 23
		 'stmt', 2,
sub
#line 382 "syncdiff_cfg_parser.y"
{ set_auto($_[2]); }
	],
	[#Rule 24
		 'stmt', 2,
sub
#line 384 "syncdiff_cfg_parser.y"
{ set_bak_dir($_[2]); }
	],
	[#Rule 25
		 'stmt', 2,
sub
#line 386 "syncdiff_cfg_parser.y"
{ set_bak_gen($_[2]); }
	],
	[#Rule 26
		 'host_list', 0, undef
	],
	[#Rule 27
		 'host_list', 2,
sub
#line 392 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[2], 0); }
	],
	[#Rule 28
		 'host_list', 4,
sub
#line 394 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[4], 0); }
	],
	[#Rule 29
		 'host_list', 5, undef
	],
	[#Rule 30
		 'host_list_slaves', 0, undef
	],
	[#Rule 31
		 'host_list_slaves', 2,
sub
#line 401 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[2], 1); }
	],
	[#Rule 32
		 'host_list_slaves', 4,
sub
#line 403 "syncdiff_cfg_parser.y"
{ add_host($_[2], $_[4], 1); }
	],
	[#Rule 33
		 'excl_list', 0, undef
	],
	[#Rule 34
		 'excl_list', 2,
sub
#line 409 "syncdiff_cfg_parser.y"
{ add_patt(0, on_cygwin_lowercase($_[2])); }
	],
	[#Rule 35
		 'incl_list', 0, undef
	],
	[#Rule 36
		 'incl_list', 2,
sub
#line 415 "syncdiff_cfg_parser.y"
{ add_patt(1, on_cygwin_lowercase($_[2])); }
	],
	[#Rule 37
		 'comp_list', 0, undef
	],
	[#Rule 38
		 'comp_list', 2,
sub
#line 421 "syncdiff_cfg_parser.y"
{ add_patt(2, on_cygwin_lowercase($_[2])); }
	],
	[#Rule 39
		 '@2-1', 0,
sub
#line 426 "syncdiff_cfg_parser.y"
{ new_action(); }
	],
	[#Rule 40
		 'action', 5, undef
	],
	[#Rule 41
		 'action_stmts', 0, undef
	],
	[#Rule 42
		 'action_stmts', 3, undef
	],
	[#Rule 43
		 'action_stmt', 2, undef
	],
	[#Rule 44
		 'action_stmt', 2, undef
	],
	[#Rule 45
		 'action_stmt', 2,
sub
#line 440 "syncdiff_cfg_parser.y"
{ set_action_logfile($_[2]); }
	],
	[#Rule 46
		 'action_stmt', 1,
sub
#line 442 "syncdiff_cfg_parser.y"
{ set_action_dolocal(); }
	],
	[#Rule 47
		 'action_pattern_list', 0, undef
	],
	[#Rule 48
		 'action_pattern_list', 2,
sub
#line 448 "syncdiff_cfg_parser.y"
{ add_action_pattern(on_cygwin_lowercase($_[2])); }
	],
	[#Rule 49
		 'action_exec_list', 0, undef
	],
	[#Rule 50
		 'action_exec_list', 2,
sub
#line 454 "syncdiff_cfg_parser.y"
{ add_action_exec($_[2]); }
	]
],
                                  @_);
    bless($self,$class);
}

#line 457 "syncdiff_cfg_parser.y"



1;
