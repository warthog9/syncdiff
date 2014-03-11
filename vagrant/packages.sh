#!/bin/sh

# Install cpanm dependency
if [ ! -f /usr/local/bin/cpanm ]; then
  curl -L http://cpanmin.us | perl - --sudo App::cpanminus
fi
