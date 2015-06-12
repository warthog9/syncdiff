use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(code => <<'YAPP');
require Parse::Yapp;
sub process_yapp_files {
    my $self = shift;
    print "Build yapp files\n";

    my $yapp_file = q{syncdiff_cfg_parser.y};
    my ($pack_file, $pack_name) = ("FileSync/SyncDiff/ParseCfg.pm", "FileSync::SyncDiff::ParseCfg");
    eval {
        my ($yapp) = Parse::Yapp->new(inputfile => $yapp_file);
        open(my $fh, '>', $pack_file);
        print $fh $yapp->Output(classname => $pack_name);
        close($fh);
    };
    if ($@) {
        print "Can not build yapp files $! \n";
    }
}
YAPP

my $builder = $class->new(
    module_name         => 'SyncDiff',
    dist_name           => 'syncdiff',
    dist_version        => '0.1',
    license             => 'lgpl_2_1',
    dist_author         => 'warthog9@eaglescrag.net',
    dist_abstract       => 'SyncDiff(erent) is a statefull rsync-like file synchronizer. Think rsync + git + csync2 + unison',
    requires => {
        'Module::Build'             => 0.4214,
        'Moose'                     => 1.15,
        'Parse::Lex'                => 0,
        'DBD::SQLite'               => 1.27,
        'Digest::SHA'               => 5.47,
        'Parse::Yapp::Driver'       => 1.05,
        'File::FnMatch'             => 0.02,
        'Try::Tiny'                 => 0.11,
        'File::Rdiff'               => 1.0,
        'JSON::XS'                  => 2.27,
        'URI'                       => 1.67,
    },
    meta_merge     => {
        resources => {
            repository  => 'https://github.com/warthog9/syncdiff',
        },
    },
    test      => {TESTS => 't/*.t'}
);
$builder->add_build_element('yapp');
$builder->create_build_script();
print "Have a great day!\n";
