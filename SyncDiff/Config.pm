#!/usr/bin/perl

#package SyncDiff::Config 0.01;
package SyncDiff::Config;
$SyncDiff::Config::VERSION = '0.01';

use Moose;

use Parse::Lex;
use SyncDiff::ParseCfg;
use SyncDiff::Util;

use Data::Dumper;

has 'config' => (
	is	=> 'ro',
	isa	=> 'HashRef',
	writer	=> '_write_config',
); # end config

has 'lexer' => (
	is	=> 'ro',
	isa	=> 'Object',
); # end config
##	writer	=> '_write_config',

sub read_config {
	my ($self, $config_file) = @_;

#	print "---------------------------\n";
#	print "config file:\n";
#	print "---------------------------\n";
#	print Dumper $config_file;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	open( my $fh, "<", $config_file) or die "can't open $config_file - you've done something horribly wrong! $!\n";

	my @tokens = (
		qw(
			TK_BLOCK_BEGIN	[\{]
			TK_BLOCK_END	[\}]
			TK_POPEN	[\(]
			TK_PCLOSE	[\)]
			TK_STEND	[\;]
			TK_COLON	[\:]
			TK_AT		[\@]
			TK_IGNORE	ignore
			TK_GROUP	group
			TK_HOST		host
			TK_EXCL		exclude
			TK_INCL		include
			TK_COMP		compare
			TK_KEY		key
			TK_AUTO		auto
			TK_ACTION	action
			TK_PATTERN	pattern
			TK_EXEC		exec
			TK_LOGFILE	logfile
			TK_DOLOCAL	do-local
			TK_PREFIX	prefix
			TK_ON		on
			TK_BAK_DIR	backup-directory
			TK_BAK_GEN	backup-generations
			TK_NOCYGLOWER	no-cygwin-lowercase
			COMMENT		\/\/.*\n*
			NL		[\n\r]
		),
		qw(COMMENT), "#.*\n*" ,
		qw(TK_STRING),	[qw(" (?:[^"]+|"")* ")],
		qw(TK_STRING), q([^\s;:{}\(\)\@\n\r\#]+),
		qw(config), sub {
			print "got an additional config file $_[1]\n";
		},
		qw(ERROR  .*), sub {
			die qq!can\'t analyze: "$_[1]"!;
		},
	);
#		qw(COMMENT), qw( \#.*\n* ),
#		qw(TK_STRING),	qw(\S+),
#			COMMENT		#.*\n*


#	print "SyncDiff::Config->read_config() - Turning trace on\n";
#	Parse::Lex->trace;  # Class method
#	print "SyncDiff::Config->read_config() - Trace is enabled\n";

	#print Dumper $self;

##	print Dumper \@tokens;
##	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my $lexer = Parse::Lex->new(@tokens);
	#$lexer->from($fh);

##	print "SyncDiff::Config->read_config() - Made it past adding the tokens\n";

	#bless $lexer, "Parse::Lex";

	$self->{lexer} = \$lexer;

	#my $new_lexer = $self->{lexer};

	#bless $new_lexer, "Parse::Lex";

##	print "-------------------------------------\n";
##	print Dumper $self;
##	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	print "Tokenization of DATA:\n";

##	print "Reference: ". ref( ${ $self->{lexer} } ) ."\n";

	my $parser = SyncDiff::ParseCfg->new();


	my $callback_ref_lex = mitm_callback(\&lex, $self);

	my $tempvar = $/;
	undef $/;
	my $file_data = <$fh>;
	$/ = $tempvar;

	$parser->YYData->{DATA} = $file_data;
	$lexer->from( $parser->YYData->{DATA} );

##	print "SyncDiff::Config->read_config() - About to run the parser...\n";

	$parser->YYParse(
				YYlex => $callback_ref_lex,
				YYerror => \&perl_error,
			);
			#	YYdebug => 0x1F,

##	print "SyncDiff::Config->read_config() - Made it past the parser\n";
				##YYdebug => 0x1F,

#	print "#########################################################\n";
#	print Dumper \$parser;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

#	my %groups = $parser->get_groups();
#	print "#########################################################\n";
#	print Dumper \%groups;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

#	print "#########################################################\n";
#	print Dumper \$self;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my %config;

	#print Dumper $self->config;
	if( defined undef ){
		%config = $self->config;
	}

#	print "#########################################################\n";
#	print Dumper $self->config;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	my %group_temp = $parser->get_groups();
	$config{'groups'} = \%group_temp;
	my %prefixes_temp = $parser->get_prefixes();
	$config{'prefixes'} = \%prefixes_temp;
	( $config{'ignore_uid'}, $config{'ignore_gid'}, $config{'ignore_mod'} ) = $parser->get_ignores();

#	print "#########################################################\n";
#	print Dumper \%config;
#	print "---------------------------------------------------------\n";
#	print Dumper %group_temp;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

#	print "#########################################################\n";
#	print Dumper \%config;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";

	$self->_write_config( \%config );

#	print "#########################################################\n";
#	print Dumper $self->config;
#	print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";
} # end read_config()

sub lex {
	my($self) = @_;
	
	my $token = ${ $self->{lexer} }->next;

	#return("\n", "\n") if( $token->name eq "NL" );
	while( $token->name eq "NL" || $token->name eq "COMMENT"){
#		print "Lexer: Line $.\t";
#		print "Lexer: Type: ", $token->name, "\t";
#		print "Lexer: Getstring: ". $token->getText ."\t";
#		print "Lexer: Content:->", $token->text, "<-\n";
		$token = ${ $self->{lexer} }->next;
	}

#	print "Lexer: Line $.\t";
#	print "Lexer: Type: ", $token->name, "\t";
#	print "Lexer: Getstring: ". $token->getText ."\t";
#	print "Lexer: Content:->", $token->text, "<-\n";

	return ('', undef) if ${ $self->{lexer} }->eoi;
	return ($token->name, $token->name) if( $token->getText eq "" );
	return ($token->name, $token->getText);
} # end lex()

sub perl_error {
#	my $self = shift;
#	warn "Error: found ",$self->YYCurtok,
#		" and expecting one of ",join(" or ",$self->YYExpect);
#	print Dumper \@_;
} # end perl_error()

sub get_truepath {
	my( $self, $path ) = @_;

	if( $path =~ /^\// ){
		return $path;
	}

	if( $path =~ /^%/ ){
		my $prefix = $path;
		$prefix =~ s/^\%([^\%]+)\%.*$/$1/;

##		print "SyncDiff::Config->get_truepath() - prefix: ". $prefix ."\n";

		#print Dumper $self->{config}->{prefixes};

		my $prefix_path = $self->{config}->{prefixes}->{$prefix};

		my $truepath = $path;
		$truepath =~ s/%$prefix%/$prefix_path/;

		return $truepath;
	}

	return undef;
}

#no moose;
__PACKAGE__->meta->make_immutable;

1;
