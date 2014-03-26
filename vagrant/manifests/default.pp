# Install EPEL
class {'epel': }

# Install IUS
yumrepo { "IUS":
  baseurl => "http://dl.iuscommunity.org/pub/ius/stable/$operatingsystem/$operatingsystemmajrelease/$architecture",
  descr => "IUS Community repository",
  enabled => 1,
  gpgcheck => 0,
}

# Ensure puppet is installed and at latest version
package { 'puppet':
  ensure => 'latest',
  #require => Package['puppetlabs-release'],
}

# Ensure syncdiff prerequsites are present
package { 'librsync-devel': ensure  => 'present', }
#package { 'librsync': ensure  => 'present', }
package { 'perl-CPAN': ensure  => 'present', }

package { 'perl-Module-Build': ensure => 'present', }
package { 'perl-Moose': ensure => 'present', }
package { 'perl-ParseLex': ensure => 'present', }
package { 'perl-DBD-SQLite': ensure => 'present', }
package { 'perl-Digest-SHA1': ensure => 'present', }
package { 'perl-Parse-Yapp': ensure => 'present', }
package { 'perl-File-FnMatch': ensure => 'present', }
package { 'perl-Try-Tiny': ensure => 'present', }
package { 'perl-JSON-XS': ensure => 'present', }
