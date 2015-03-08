#!/bin/sh

mkdir /dev/pts
/bin/mount -t devpts devpts /dev/pts
/sbin/telnetd -l /bin/login

