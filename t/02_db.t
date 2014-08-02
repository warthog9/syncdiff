use Test::More;
use lib '../';
use FileSync::SyncDiff::Config;

use_ok('FileSync::SyncDiff::DB');

my $file        = 'psync.sqlite';
my $config_file = 'syncdiff.cfg';

my $config = FileSync::SyncDiff::Config->new();
$config->read_config( $config_file );

ok(my $dbconnection = FileSync::SyncDiff::DB->new( config => $config, file => $file ),'create database object');
ok($dbconnection->connect_and_fork(),'run working with database');

done_testing();