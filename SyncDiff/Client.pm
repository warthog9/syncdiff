#!/usr/bin/perl

package SyncDiff::Client;
$SyncDiff::Client::VERSION = '0.01';

use Moose;

extends qw(SyncDiff::Forkable);

#
# Needed to communicate with other modules
#

use SyncDiff::File;
use SyncDiff::Util;
use SyncDiff::Protocol::v1;

#
# Other Includes
#

use JSON::XS;
use MIME::Base64;
use IO::Socket;
use IO::Handle;

use Scalar::Util qw(looks_like_number);

#
# Debugging
#

use Data::Dumper;

# End Includes

#
# moose variables
#

has 'config_options' => (
		is	=> 'rw',
		isa	=> 'HashRef',
		required => 1,
		);

has 'group' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'groupbase' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'dbref' => (
		is	=> 'rw',
		isa	=> 'Object',
		required => 1,
		);

has 'groupbase_path' => (
		is	=> 'rw',
		isa	=> 'Str',
		required => 1,
		);

has 'socket' => (
		is	=> 'rw',
		isa	=> 'IO::Socket::INET',
		);

has 'protocol_version' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

has 'protocol_object' => (
		is	=> 'rw',
		isa	=> 'Str',
		);

# End variables

#
# Need to override this from Forkable
#

override 'run_child' => sub {
	my( $self ) = @_;

	$self->recv_loop();
}; # end run_child()

sub fork_and_connect {
	my( $self ) = @_;

	print "Client::fork_and_connect - ". $self->group ." - ". $self->groupbase ."\n";
	print Dumper $self->config_options;

	print "Client::fork_and_connect - path\n";
	print Dumper $self->groupbase_path;

	if( ! -e $self->groupbase_path ){
		die( "Path: ". $self->groupbase_path ." does *NOT* exist in group ". $self->group ." - sadly dying now.\n" );
	}

	#
	# Going chroot
	# 	everything else we need should
	# 	be in the chroot, or accessible
	# 	via pipes
	#
	chroot( $self->groupbase_path );
	chdir("/");

	#
	# Ok now we need to connect to the
	# various hosts associated with
	# this group.  There are two obvious
	# ways to do this
	#
	# (1) do them sequentially - this is 
	#     probably ok but for whatever
	#     reason it doesn't seem to be
	#     the best option
	# (2) run them all in their own 
	#     process and chew up all the
	#     bandwidth
	#
	# considering that we are already
	# potentially transfering files in
	# parallel I think I'm going to
	# play it safe and do it sequentially
	# *FOR NOW*
	#
	# I.E. this should be a config option
	# at some point in the future
	#

	foreach my $host ( @{ $self->config_options->{groups}->{ $self->group }->{host} } ){
		print "Host: ". $host ."\n";
		my $ip = $self->dbref->gethostbyname( $host );
		print "Ip: ". $ip ."\n";
		my $sock = new IO::Socket::INET (
						PeerAddr => $ip,
						PeerPort => '7070',
						Proto => 'tcp',
						);
		if( ! $sock ){
			print "Could not create socket: $!\n";
			next;
		} # end skipping if the socket is broken

		$self->socket( $sock );

		print $sock "Hello World!\n";
		$self->request_protocol_versions();
		close( $sock );
	} # end foreach $host
} # end fork_and_connect()

sub request_protocol_versions {
	my( $self ) = @_;

	my %request = (
		'operation'	=> 'request_protocol_versions',
	);

	my $versions = $self->basic_send_request( %request );

	print Dumper $versions;

	my $highest_proto_supported = "1.99";
	my $proto_to_use = 0;

	foreach my $ver ( @{$versions} ){
		print "Version: ". $ver ."\n";

		if( ! looks_like_number($ver) ){
			print "*** $ver is not a version number\n";
			next;
		}

		if(
			$ver <= $highest_proto_supported
			&&
			$ver >= $proto_to_use
		){
			$proto_to_use = $ver;
			print "Currently selected Protocol Version: ". $ver ."\n";
		}
	} # end foreach $ver

	$self->protocol_version( $proto_to_use );	

	my $protocol_obj;

	if(
		$proto_to_use >= 1.0
		&&
		$proto_to_use < 2.0
	){
		$protocol_obj = SyncDiff::Protocol::v1->new( socket => $self->socket, version => $proto_to_use );
	}

	$protocol_obj->setup();
} # end request_protocol_version()

sub basic_send_request {
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
