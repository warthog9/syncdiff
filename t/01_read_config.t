use Test::More;
use lib '../';

use_ok('FileSync::SyncDiff::Config');

my $config_file = 'syncdiff.cfg';
ok(my $config = FileSync::SyncDiff::Config->new(),'create config object');
ok($config->read_config( $config_file ),'read configuration file');

done_testing();