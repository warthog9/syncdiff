#!/usr/bin/perl

package SyncDiff::Protocol::v1;
$SyncDiff::Protocol::v1::VERSION = '0.01';
use Moose;

#
# Other Includes
#

use JSON::XS;

#
# Debugging
#

use Data::Dumper;

#
# Getting on with it
#

has 'socket' => (
		is	=> 'rw',
		isa	=> 'IO::Socket::INET',
		required => 1,
		);

has 'version' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

sub setup {
	my( $self ) = @_;

	my %request = (
		request_version => $self->version
	);

	my $response = $self->send_request( %request );

	print Dumper $response;
} # end setup()

sub send_request {
	my( $self, %request ) = @_;

	my $json = encode_json( \%request );

	my $socket = $self->socket;

	print $socket $json ."\n";

	my $line = undef;

	while( $line = <$socket> ){
		if( defined $line  ){
			chomp( $line );
			last if( $line ne "" );
		}
	}

	chomp( $line );

	if( $line eq "0" ){
		return 0;
	}

	my $response = decode_json( $line );

	print Dumper $response;
	print "Ref: ". ref( $response ). "\n";

	if( ref( $response ) eq "ARRAY" ){
		return $response;
	}

	if( defined $response->{ZERO} ){
		return 0;
	}

	if( defined $response->{SCALAR} ){
		return $response->{SCALAR};
	}

	if( defined $response->{ARRAY} ){
		return $response->{ARRAY};
	}

	return $response;
} # end send_request()

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
