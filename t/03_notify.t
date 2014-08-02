use Test::More;
use lib '../';
use FileSync::SyncDiff::Config;
use FileSync::SyncDiff::DB;

use_ok('FileSync::SyncDiff::Notify');

my $file        = 'psync.sqlite';
my $config_file = 'syncdiff.cfg';

my $config = FileSync::SyncDiff::Config->new();
$config->read_config( $config_file );

my $dbconnection = FileSync::SyncDiff::DB->new( config => $config, file => $file );
$dbconnection->connect_and_fork();

ok(my $notify = FileSync::SyncDiff::Notify->new( config => $config, dbref => $dbconnection ),'create notify object');
ok($notify->start(),'enable notify running flag and save it in cache memory');
ok(defined $notify->stop(),'disabled notify running flag and save it in cache memory');

done_testing();