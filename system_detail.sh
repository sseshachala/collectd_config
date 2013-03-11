#!/bin/bash

COLLECTD_HOSTNAME="${COLLECTD_HOSTNAME:-localhost}"

SYSTEM=`uname -s`
ARCH=`uname -m`


if [ -f /etc/lsb-release ]; then
  . /etc/lsb-release
  DIST=$DISTRIB_DESCRIPTION
elif [ -f /etc/debian_version ]; then
  DIST=`cat /etc/debian_version`
elif [ -f /etc/redhat-release ]; then
  DIST=`cat /etc/redhat-release`
fi

HOSTNAME=`hostname`

echo system: $SYSTEM
echo arch: $ARCH
echo dist: $DIST
echo host: $HOSTNAME
ip -4 -o addr | awk '!/^[0-9]*: ?lo|link\/ether/ {print "IP_"$2": "$4}'
ip -6 -o addr | awk '!/^[0-9]*: ?lo|link\/ether/ {print "IP6_"$2": "$4}'
ip -o link | awk '/^[0-9]*: .*link\/ether/ {print "MAC_"$2" "$(NF-2)}'
