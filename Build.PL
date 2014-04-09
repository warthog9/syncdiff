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
        'Moose'                     => 1.15,
	'MooseX::Types::Moose'      => 0,
	'MooseX::FileAttribute'     => 0,	
        'Parse::Lex'                => 0,
        'DBD::SQLite'               => 1.27,
        'Digest::SHA'               => 5.47,
        'Parse::Yapp::Driver'       => 1.05,
        'File::FnMatch'             => 0.02,
        'Try::Tiny'                 => 0.11,
        'File::Rdiff'               => 1.0,
        'JSON::XS'                  => 2.27,
	'AnyEvent'		    => 0,
	'Linux::Inotify2'	    => 0,
	'File::Next'		    => 0,
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
