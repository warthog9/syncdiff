#!/bin/bash
# created on March 1st 2014
# author Prithviraj M Billa

echo "Installing required libraries and tools"
sudo apt-get install gcc g++ librsync-dev libyaml-libyaml-perl libyaml-appconfig-perl libyaml-dev curl make

echo "Installing perl and other tools"
curl -L http://xrl.us/installperlnix | bash

echo "Installing required perl modules"
cpan -i Parse::Lex
cpan -i YAML
cpan -i File::Rdiff
cpan -i Moose.pm
cpan -i JSON::XS
cpan -i DBD::SQLite
cpan -i File::FnMatch
cpan -i Parse::Yapp
