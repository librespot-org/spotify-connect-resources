# $Id: Makefile.Shannon 432 2006-03-20 03:45:50Z mwp $
#
# Edit this part to match your compilation environment.
#

#
# Compile time definitions:
#   use -DIS_LITTLE_ENDIAN when compiling for a little endian architecture
#
# OPTIONS = -DIS_LITTLE_ENDIAN

#
# C compiler and flags.
# Any ANSI compliant C compiler will work.
#
CC = gcc
CFLAGS = $(OPTIONS) $(ARCH) -O3 -std=c99 -Wall
LDFLAGS =

#
# Miscellaneous utilities.
# Define these to suit your environment.
#
TAR = tar
RM = rm

SHELL = /bin/sh

VERSION = 1.0

# End of configuration

SHN_SRC = Shannon.h hexlib.h ShannonRef.c \
	ShannonTest.c ShannonFast.c hexlib.c\
	Makefile ShannonPaper.pdf
SHNREF_OBJS = ShannonRef.o ShannonTest.o hexlib.o
SHNFAST_OBJS = ShannonFast.o ShannonTest.o hexlib.o

all: ShannonRef ShannonFast

ShannonRef: $(SHNREF_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(SHNREF_OBJS)

ShannonFast: $(SHNFAST_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(SHNFAST_OBJS)

ShannonFast.o: Shannon.h
ShannonRef.o: Shannon.h
Shannontest.o: Shannon.h hexlib.h
hexlib.o: hexlib.h

dist: Shannon-$(VERSION).tgz
Shannon-$(VERSION).tgz: README.SHN $(SHN_SRC)
	$(TAR) zcf $@ README.SHN $(SHN_SRC)

test: Shannontest
Shannontest: ShannonRef ShannonFast
	-./ShannonRef -test
	-./ShannonFast -test

time: Shannontime
Shannontime: ShannonRef ShannonFast
	./ShannonRef -time
	./ShannonFast -time

clean: Shannonclean
Shannonclean:
	$(RM) -f ShannonRef $(SHNREF_OBJS)
	$(RM) -f ShannonFast $(SHNFAST_OBJS)
	$(RM) -f Shannon-$(VERSION).tgz
