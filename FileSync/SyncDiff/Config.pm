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

#package FileSync::SyncDiff::Config 0.01;
package FileSync::SyncDiff::Config;
$FileSync::SyncDiff::Config::VERSION = '0.01';

use Moose;

use Parse::Lex;
use FileSync::SyncDiff::ParseCfg;
use FileSync::SyncDiff::Util;

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
		qw(TK_STRING),	[qw(["'] (?:[^"]+|"")* ["'])],
		qw(TK_STRING), q([^\s;:{}\(\)\@\n\r\#]+),
		qw(config), sub {
			print STDERR "got an additional config file $_[1]\n";
		},
		qw(ERROR  .*), sub {
			die qq!can\'t analyze: "$_[1]"!;
		},
	);

	my $lexer = Parse::Lex->new(@tokens);

	$self->{lexer} = \$lexer;

	print STDERR "Tokenization of DATA:\n";

	my $parser = FileSync::SyncDiff::ParseCfg->new();


	my $callback_ref_lex = mitm_callback(\&lex, $self);

	my $tempvar = $/;
	undef $/;
	my $file_data = <$fh>;
	$/ = $tempvar;

	$parser->YYData->{DATA} = $file_data;
	$lexer->from( $parser->YYData->{DATA} );

	$parser->YYParse(
				YYlex => $callback_ref_lex,
				YYerror => \&perl_error,
			);

	my %config;

	if( defined undef ){
		%config = $self->config;
	}

	my %group_temp = $parser->get_groups();
	$config{'groups'} = \%group_temp;
	my %prefixes_temp = $parser->get_prefixes();
	$config{'prefixes'} = \%prefixes_temp;
	( $config{'ignore_uid'}, $config{'ignore_gid'}, $config{'ignore_mod'} ) = $parser->get_ignores();

	$self->_write_config( \%config );
} # end read_config()

sub lex {
	my($self) = @_;
	
	my $token = ${ $self->{lexer} }->next;

	if ( $token->name =~ m/^TK_STRING$/ ) {
		# Cut ' and " in beginning
		(my $text = $token->text) =~ m/(['"])?(?<str>.*?)\g{-2}/;
		$token->text($+{str});
	}

	while( $token->name eq "NL" || $token->name eq "COMMENT"){
		$token = ${ $self->{lexer} }->next;
	}

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

		my $prefix_path = $self->{config}->{prefixes}->{$prefix};

		my $truepath = $path;
		$truepath =~ s/%$prefix%/$prefix_path/;

		return $truepath;
	}

	return undef;
} # end get_truepath()

sub get_group_config {
	my( $self, $group ) = @_;

	my %group_config = (
		'ignore_mod'	=> $self->config->{ignore_mod},
		'ignore_uid'	=> $self->config->{ignore_uid},
		'ignore_gid'	=> $self->config->{ignore_gid}, 
		);
	$group_config{groups}->{$group} = $self->config->{groups}->{$group};

	return \%group_config;
} # end get_group_config()

__PACKAGE__->meta->make_immutable;

1;
