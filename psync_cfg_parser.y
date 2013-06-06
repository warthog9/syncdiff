%{ # start of the code section

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

