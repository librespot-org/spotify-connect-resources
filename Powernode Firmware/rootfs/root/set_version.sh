#!/bin/bash -e
sed -r -i "s:(my \\\$VERSION = [\"'])([^\"']*)([\"']):\1$1\3:" cp.pl
