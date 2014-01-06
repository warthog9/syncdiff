#!/usr/bin/perl

package SyncDiff::SenderReciever;
$SyncDiff::SenderReciever::VERSION = '0.01';

use Moose;

extends qw(SyncDiff::Forkable);

#
# Needed to communicate with other modules
#

use SyncDiff::Util;
use SyncDiff::Protocol::v1;

#
# Other Includes
#

use JSON::XS;
use MIME::Base64;
use IO::Socket;
use IO::Handle;
use Try::Tiny;

#
# Debugging
#

use Data::Dumper;

# End Includes

#
# moose variables
#

has 'socket' => (
		is	=> 'rw',
		isa	=> 'IO::Socket::INET',
		);

#
# Ridiculous Globals (for now)
#
my $TIMEOUT = 300;

# End variables

sub recv_loop {
	my ( $self ) = @_;

	my $sock = new IO::Socket::INET (
				LocalPort => '7070',
				Proto => 'tcp',
				Listen => 1,
				Reuse => 1,
				);
	die "Could not create socket: $!\n" unless $sock;

	while( my $new_sock = $sock->accept() ){
		my $child;

		if( ( $child = fork() ) == 0 ){
			# child process
			print Dumper $new_sock;
			$self->socket( $new_sock );
			$self->process_request();
		}
	} # end while( $new_sock = $sock->accept() ) loop
} # end recv_loop()

sub process_request {
	my( $self ) = @_;

	my $line = undef;
	my $socket = $self->socket;

	print Dumper $socket;

	if( ! defined $socket ){
		return;
	}

	while( $line = <$socket> ){
		chomp($line);

		print "Server got:\n";
		print Dumper $line;

		my $response = $self->_process_request( $line );

		if(
			$response eq "0"
		){
			my %temp_resp = (
				ZERO	=> "0",
			);
			$response = \%temp_resp;
		}

##		print "Reference check: ". ref( $response ) ."\n";
##		print Dumper $response;

		my $ref_resp = ref( \$response );

		if(
			! defined $ref_resp
			||
			$ref_resp eq "SCALAR"
			||
			$ref_resp eq ""
		){
			my %temp_resp = (
				SCALAR	=> $response,
			);
			$response = \%temp_resp;
		}

		my $json_response = encode_json( $response );

		print $socket $json_response ."\n";
	}
} # end recv_loop()

sub send_request {
	my( $self, %request ) = @_;

	my $json = encode_json( \%request );

	my $socket = $self->socket;

	print $socket $json ."\n";

	my $line = undef;

	# attach a timeout to trying to listen to the
	# socket in case things take forever and we
	# should just give up and die
	eval {
		alarm($TIMEOUT);
		while( $line = <$socket> ){
			if( defined $line  ){
				chomp( $line );
				last if( $line ne "" );
			}
		} # end while loop waiting on socket to return
		return 0;
	}; # end eval / timeout 

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
