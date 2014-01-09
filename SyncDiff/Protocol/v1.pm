#!/usr/bin/perl

package SyncDiff::Protocol::v1;
$SyncDiff::Protocol::v1::VERSION = '0.01';
use Moose;

extends qw(SyncDiff::SenderReciever);

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

has 'dbref' => (
		is	=> 'rw',
		isa	=> 'Object',
		required => 0,
		);

sub setup {
	my( $self ) = @_;

	my %request = (
		request_version => $self->version
	);

	my $response = $self->send_request( %request );

	print "Protocol V1 - Setup - Version request response:\n";
	print Dumper $response;

	if( $response ne "1.0" ){  # This is the only protocol version we support right now
		print "We don't currently support protocol version: ". $response ." - bailing out\n";
		exit(1);
	}
} # end setup()

#
# This is the main routine, once the protocol version
# has been figured out there's no point in the parent
# trying to tell all the children how to work, so 
# it will call into run() and basically let things
# go from there.  It's then up to the protocol to 
# negotiate with itself on how the rest of the interaction
# works.  Why?  So that future protocols can be
# completely different, who knows maybe someone
# will build a p2p backend that's more BitTorrent
# like that doesn't suck.
#

sub client_run {
	my( $self ) = @_;

	print "Client is now running with Protocol major version 1\n";

	my $remote_current_log_position = $self->shareCurrentLogPosition();
}

sub shareCurrentLogPosition {
	my( $self ) = @_;

	my $logPosition = $self->dbref->current_log_position();

	print "Log position is:\n";
	print Dumper $logPosition

}

	
sub getVersion {
	my( $self ) = @_;
	
	return "1.0"
}

#
# This is the main routine for the server side of things
# shouldn't be *TOO* dissimilar to the client, but yeah
#

sub server_process_request {
	my( $self, $response ) = @_;

	print "Server version 1 got response: \n";
	print Dumper $response;

	if( ! exists( $response->{v1_operation} ) ){
		return;
	}

	if( $response->{v1_operation} eq "getLogPosition" ){
		print "DBref:\n";
		print Dumper $self->dbref;
		my $logPosition = $self->dbref->current_log_position();
		print "Found log position on Server:\n";
		print Dumper $logPosition;
		return $logPosition;
	}
}

#no moose;
__PACKAGE__->meta->make_immutable;
#__PACKAGE__->meta->make_immutable(inline_constructor => 0,);

1;
