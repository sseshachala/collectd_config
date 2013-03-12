#!/bin/bash

TIME=`date +%s`
HOSTNAME="${COLLECTD_HOSTNAME:-localhost}"

SYSTEM=`uname -s`
ARCH=`uname -m`
CUSTOMER=$1

if [ -f /etc/lsb-release ]; then
  . /etc/lsb-release
  DIST=$DISTRIB_DESCRIPTION
elif [ -f /etc/debian_version ]; then
  DIST=`cat /etc/debian_version`
elif [ -f /etc/redhat-release ]; then
  DIST=`cat /etc/redhat-release`
fi

HOSTNAME=`hostname`

msg="system: $SYSTEM^customer: $CUSTOMER^arch: $ARCH^dist: $DIST^host: $HOSTNAME^"
msg=$msg`ip -4 -o addr | awk 'BEGIN{ORS="^";}!/^[0-9]*: ?lo|link\/ether/ {print "IP_"$2": "$4}'`
msg=$msg`ip -6 -o addr | awk 'BEGIN{ORS="^";}!/^[0-9]*: ?lo|link\/ether/ {print "IP6_"$2": "$4}'`
msg=$msg`ip -o link | awk 'BEGIN{ORS="^";}/^[0-9]*: .*link\/ether/ {print "MAC_"$2" "$(NF-2)}'`

echo PUTNOTIF severity=okay time=$TIME host=$HOSTNAME plugin=server_data message=\"$msg\"
