%{ # start of the code section

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

%} # end of the code section

%expect 2

%union {
	char *txt;
}

%token TK_BLOCK_BEGIN TK_BLOCK_END TK_STEND TK_AT TK_AUTO
%token TK_IGNORE TK_GROUP TK_HOST TK_EXCL TK_INCL TK_COMP TK_KEY
%token TK_ACTION TK_PATTERN TK_EXEC TK_DOLOCAL TK_LOGFILE TK_NOCYGLOWER
%token TK_PREFIX TK_ON TK_COLON TK_POPEN TK_PCLOSE
%token TK_BAK_DIR TK_BAK_GEN
%token <txt> TK_STRING

%%

config:
	/* empty */
|	block config
;

block:
	block_header block_body
|	TK_PREFIX TK_STRING
		{ new_prefix($_[2]); }
		TK_BLOCK_BEGIN prefix_list TK_BLOCK_END
		{ }
|	TK_IGNORE ignore_list TK_STEND
|	TK_NOCYGLOWER TK_STEND
		{ disable_cygwin_lowercase_hack(); }
;

ignore_list:
	/* empty */
|	TK_STRING ignore_list
		{ new_ignore($_[1]); }
;

prefix_list:
	/* empty */
|	prefix_list TK_ON TK_STRING TK_COLON TK_STRING TK_STEND
		{ new_prefix_entry($_[3], on_cygwin_lowercase($_[5])); }
;

block_header:
	TK_GROUP
		{ new_group(0);  }
|	TK_GROUP TK_STRING
		{ new_group($_[2]); }
;

block_body:
	TK_BLOCK_BEGIN stmts TK_BLOCK_END
		{ check_group(); }
;

stmts:
	/* empty */
|	stmt TK_STEND stmts
|	action stmts
;

stmt:
	TK_HOST host_list
|	TK_EXCL excl_list
|	TK_INCL incl_list
|	TK_COMP comp_list
|	TK_KEY TK_STRING
		{ set_key($_[2]); }
|	TK_AUTO TK_STRING
		{ set_auto($_[2]); }
|	TK_BAK_DIR TK_STRING
		{ set_bak_dir($_[2]); }
|	TK_BAK_GEN TK_STRING
		{ set_bak_gen($_[2]); }
;

host_list:
	/* empty */
|	host_list TK_STRING
		{ add_host($_[2], $_[2], 0); }
|	host_list TK_STRING TK_AT TK_STRING
		{ add_host($_[2], $_[4], 0); }
|	host_list TK_POPEN host_list_slaves TK_PCLOSE host_list
;

host_list_slaves:
	/* empty */
|	host_list_slaves TK_STRING
		{ add_host($_[2], $_[2], 1); }
|	host_list_slaves TK_STRING TK_AT TK_STRING
		{ add_host($_[2], $_[4], 1); }
;

excl_list:
	/* empty */
|	excl_list TK_STRING
		{ add_patt(0, on_cygwin_lowercase($_[2])); }
;

incl_list:
	/* empty */
|	incl_list TK_STRING
		{ add_patt(1, on_cygwin_lowercase($_[2])); }
;

comp_list:
	/* empty */
|	incl_list TK_STRING
		{ add_patt(2, on_cygwin_lowercase($_[2])); }
;

action:
	TK_ACTION
		{ new_action(); }
	TK_BLOCK_BEGIN action_stmts TK_BLOCK_END
;


action_stmts:
	/* empty */
|	action_stmt TK_STEND action_stmts
;

action_stmt:
	TK_PATTERN action_pattern_list
|	TK_EXEC action_exec_list
|	TK_LOGFILE TK_STRING
		{ set_action_logfile($_[2]); }
|	TK_DOLOCAL
		{ set_action_dolocal(); }
;

action_pattern_list:
	/* empty */
|	action_pattern_list TK_STRING
		{ add_action_pattern(on_cygwin_lowercase($_[2])); }
;

action_exec_list:
	/* empty */
|	action_exec_list TK_STRING
		{ add_action_exec($_[2]); }
;

%%

