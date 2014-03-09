use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'SyncDiff',
    dist_name           => 'syncdiff',
    dist_version        => '0.1',
    license             => 'lgpl_2_1',
    dist_author         => 'warthog9@eaglescrag.net',
    dist_abstract       => 'SyncDiff(erent) is a statefull rsync-like file synchronizer. Think rsync + git + csync2 + unison',
    requires => {
	'Module::Build'             => 0.4205,
        'Moose'                     => 2.1204,
        'Parse::Lex'                => 2.15,
        'DBD::SQLite'               => 1.40,
        'Digest::SHA'               => 5.87,
        'Parse::Yapp::Driver'       => 1.05,
        'File::FnMatch'             => 0.02,
        'Try::Tiny'                 => 0.19,
        'File::Rdiff'               => 1.0,
        'JSON::XS'                  => 3.01,
    },
    meta_merge     => {
        resources => {
            repository  => 'https://github.com/warthog9/syncdiff',
        },
    },
    test      => {TESTS => 't/*.t'}
);

$builder->create_build_script();
print "Have a great day!\n";
