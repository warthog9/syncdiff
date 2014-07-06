use Test::More;

use_ok('Module::Build');
use_ok('Moose');
use_ok('Parse::Lex');
use_ok('DBD::SQLite');
use_ok('Digest::SHA');
use_ok('Parse::Yapp::Driver');
use_ok('File::FnMatch');
use_ok('Try::Tiny');
use_ok('File::Rdiff');
use_ok('JSON::XS');
use_ok('AnyEvent');
use_ok('File::Next');
use_ok('File::Pid');
use_ok('Net::Address::IP::Local');
use_ok('IPC::ShareLite');
use_ok('MooseX::FileAttribute');

if ( $^O eq 'linux' ) {
    use_ok('Linux::Inotify2');
}
elsif ( $^O eq 'freebsd' ) {
    use_ok('IO::KQueue');
}

done_testing();