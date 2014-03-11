syncdiff
========

SyncDiff(erent) is a statefull rsync-like file synchronizer.  Think rsync + git + csync2 + unison

** \*\* THIS IS ALPHA QUALITY CODE \*\* **

At any time this might eat your data
barf up errors.  Consume all your
pids, and all your memory till you
oom.  Right now this is meant to get
the basic ideas and flow out there
for review, and to get early 
feedback.  If you use this in 
production, don't blame me.
I am, however, happy to work
with folks if they want to start
testing with this, so feel
free to contact me.

Current build status: [![Build Status](https://travis-ci.org/warthog9/syncdiff.png?branch=master)](https://travis-ci.org/warthog9/syncdiff)

# Installing Dependencies

This app has a few external dependencies

	librsync
	librsync-dev

and internal dependencies

	cpanm --installdeps .

# Building

    perl Build.PL
    ./Build

# Running tests

    ./Build test

# Cleaning up

    ./Build clean

# Installing

    ./Build install

# Vagrant environment

This repository includes a basic Vagrant configuration that will bring up a 2-node test cluster.

## Requirements
 - Vagrant 1.4.x or newer
 - A Vagrant-supported virtualization provider: http://docs.vagrantup.com/v2/providers/
   - This configuration has been tested with VirtualBox, your mileage may very with other providers

##  Getting started with Vagrant

0. Run ```vagrant up``` from the repository root
1. Once the boxes have booted, you can log into them by running ```vagrant ssh server0``` or ```vagrant ssh server1```.  
2. ```cd /server``` to access the files in this repository on the virtual machine.
3. Follow the instructions above to build and install syncdiff.
