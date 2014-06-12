#!/bin/sh

# Packages that don't get along with puppet
yum install -y -q librsync-devel librsync perl-CPAN perl-Module-Build perl-Moose perl-ParseLex perl-DBD-SQLite perl-Digest-SHA1 perl-Parse-Yapp perl-File-FnMatch perl-Try-Tiny perl-JSON-XS

# Install cpanm dependency
if [ ! -f /usr/local/bin/cpanm ]; then
  curl -L http://cpanmin.us | perl - --sudo App::cpanminus
fi
