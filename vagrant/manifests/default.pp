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
package { 'librsync-devel':
  ensure  => 'present',
}
#package { 'librsync':
#  ensure  => 'present',
#}
package { 'perl-CPAN':
  ensure  => 'present',
}
package { 'perl-Module-Build':
  ensure  => 'present',
}
