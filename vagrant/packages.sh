#!/bin/sh

# Packages that don't get along with puppet
yum install -y -q librsync-devel librsync perl-CPAN perl-Module-Build perl-Moose perl-ParseLex perl-DBD-SQLite perl-Digest-SHA1 perl-Parse-Yapp perl-File-FnMatch perl-Try-Tiny perl-JSON-XS

# Install cpanm dependency
if [ ! -f /usr/local/bin/cpanm ]; then
  curl -L http://cpanmin.us | perl - --sudo App::cpanminus
fi


  # Ensure syncdiff prerequsites are present
  #   package { 'librsync-devel': ensure  => 'present', }
  #     #package { 'librsync': ensure  => 'present', }
  #       package { 'perl-CPAN': ensure  => 'present', }
  #
  #         package { 'perl-Module-Build': ensure => 'present', }
  #           package { 'perl-Moose': ensure => 'present', }
  #           ~ #package { 'perl-ParseLex': ensure => 'present', }
  #             package { 'perl-DBD-SQLite': ensure => 'present', }
  #               package { 'perl-Digest-SHA1': ensure => 'present', }
  #                 package { 'perl-Parse-Yapp': ensure => 'present', }
  #                 ~ #package { 'perl-File-FnMatch': ensure => 'present', }
  #                   package { 'perl-Try-Tiny': ensure => 'present', }
  #                     package { 'perl-JSON-XS': ensure => 'present', }
