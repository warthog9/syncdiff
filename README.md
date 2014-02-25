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

# Installing Dependencies

This app has a few external dependencies

	librsync
	librsync-dev

and internal dependencies

	./Build installdeps

# Building

    perl Build.PL

# Running tests

    ./Build test

# Cleaning up

    ./Build clean

# Installing

    ./Build install
