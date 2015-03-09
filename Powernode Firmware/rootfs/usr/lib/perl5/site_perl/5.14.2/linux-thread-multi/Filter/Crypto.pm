#===============================================================================
#
# lib/Filter/Crypto.pm
#
# DESCRIPTION
#   Module providing documentation and the version number of the Filter-Crypto
#   distribution.
#
# COPYRIGHT
#   Copyright (C) 2004-2010, 2012 Steve Hay.  All rights reserved.
#
# LICENCE
#   You may distribute under the terms of either the GNU General Public License
#   or the Artistic License, as specified in the LICENCE file.
#
#===============================================================================

package Filter::Crypto;

use 5.006000;

use strict;
use warnings;

#===============================================================================
# MODULE INITIALIZATION
#===============================================================================

our($VERSION);

BEGIN {
    $VERSION = '2.04';
}

1;

__END__

#===============================================================================
# DOCUMENTATION
#===============================================================================

=head1 NAME

Filter::Crypto - Create runnable Perl files encrypted with OpenSSL libcrypto

=head1 SYNOPSIS

    # Encrypt a Perl script using the crypt_file script. Run it as usual:
    $ crypt_file --in-place hello.pl
    $ hello.pl

    # Create a PAR archive containing an encrypted Perl script. Run it as usual:
    # (This example assumes that you also have PAR installed.)
    $ pp -f Crypto -M Filter::Crypto::Decrypt -o hello hello.pl
    $ hello

    # Display the Filter-Crypto distribution version number:
    use Filter::Crypto;
    print "This is Filter-Crypto $Filter::Crypto::VERSION\n";

=head1 DESCRIPTION

The Filter-Crypto distribution provides the means to convert your Perl files
into an encrypted, yet still runnable, format to hide the source code from
casual prying eyes.

This is achieved using a Perl source code filter.  The encrypted files, produced
using the L<Filter::Crypto::CryptFile|Filter::Crypto::CryptFile> module,
automatically have one (unencrypted) line added to the start of them that loads
the L<Filter::Crypto::Decrypt|Filter::Crypto::Decrypt> module.  The latter is a
Perl source code filter that decrypts the remaining (encrypted) part of the Perl
file on the fly when it is run.  See L<perlfilter> if you want to know more
about how Perl source code filters work.

Encrypted files can also be produced more conveniently using the B<crypt_file>
script, or (if you also have the L<PAR|PAR> module available) using the
L<PAR::Filter::Crypto|PAR::Filter::Crypto> module.  The latter can be utilized
by the standard L<PAR|PAR> tools to produce PAR archives in which your Perl
files are encrypted.

The actual encryption and decryption is performed using one of the symmetric
cipher algorithms provided by the OpenSSL libcrypto library.  The EVP library
high-level interface functions to the various cipher algorithms themselves are
used so that your choice of algorithm (and also what password or key to use) is
made simply by answering some questions when building this distribution.  See
the F<INSTALL> file for more details.

This module itself only contains this documentation and the version number of
the Filter-Crypto distribution as a whole.

=head1 WARNING

Some people regard the whole area of Perl source code encryption as being
morally offensive, given that Perl itself is open source.  However, Perl's
Artistic License does specifically allow the distribution of Perl "as part of a
larger (possibly commercial) software distribution," and many people producing
commercial Perl software are uneasy about distributing the source code in easily
accessible form for anyone to see, and want to take more practical action than
involving intellectual property rights lawyers.

That is where software like this comes in, but a word of warning is in order
regarding the security provided by this (and, indeed, any other) source code
decryption filter.

Some of the points below come from a discussion on the perl5-porters mailing
list, in the thread starting here:
F<http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2003-10/msg01169.html>;
others are taken from the L<Filter::decrypt|Filter::decrypt> manpage.

In general, it is hopeless to try to prevent everyone from getting at the source
code, especially when it is being run in an environment that you have no control
over, and even more so when the software running it (Perl) is open source
itself.

This technique can I<never> completely hide the original unencrypted source code
from people sufficiently determined to get it.  The most it can hope for is to
hide it from casual prying eyes, and to outdo everyone who is using a
precompiled Perl (at least from "regular" sources) and everyone who is not
knowledgeable enough to suitably modify the Perl source code before compiling
their own.

Perl source code decryption filters work by intercepting the source stream (read
from the encrypted file) and modifying it (in this case, decrypting it) before
it reaches the Perl parser.  Clearly, by the time the source reaches the parser
it must be decrypted, otherwise the script cannot be run.  This means that at
some stage every part of the script must be held in memory in an unencrypted
state, so anyone with the appropriate debugging skills will be able to get it.

If Perl was built with DEBUGGING then running the script with the Perl's B<-Dp>
command-line option makes this much easier.  Even without a DEBUGGING Perl, the
script can still be run under the Perl debugger (Perl's B<-d> command-line
option), whose C<l> command will list the (decrypted) source code that was fed
to the parser.

In fact, with the introduction of the Perl compiler backend modules it is now
easy to get at the decrypted source code without any debugging skills at all.
To quote L<B::Deparse>:

    B::Deparse is a backend module for the Perl compiler that generates perl
    source code, based on the internal compiled structure that perl itself
    creates after parsing a program.  The output of B::Deparse won't be exactly
    the same as the original source, since perl doesn't keep track of comments
    or whitespace, and there isn't a one-to-one correspondence between perl's
    syntactical constructions and their compiled form, but it will often be
    close.

To make debugging and deparsing more difficult, the source code decryption
filter implemented in this distribution contains checks to try to disallow the
following:

=over 4

=item *

Running under a Perl that was built with DEBUGGING (C<-DDEBUGGING>);

=item *

Running under a Perl with DEBUGGING flags enabled (B<-D> or $^D);

=item *

Running under the Perl debugger (B<-d>);

=item *

Running under the Perl compiler backend (B<-MO=Deparse>).

=back

You should also not use a Perl that was built with C debugging support enabled
(e.g. B<gcc>'s B<-g> option, or B<cl.exe>'s B</Zi> option) and should strip the
Perl executable to remove all symbols (e.g. B<gcc>'s B<-s> option).

None of the above checks are infallible, however, because unless the source code
decryption filter module is statically linked against the Perl executable then
users can always replace the Perl executable being used to run the script with
their own version, perhaps hacked in such a way as to work around the above
checks, and thus with debugging/deparsing capabilities enabled.  Such a hacked
version of the Perl executable can certainly be produced since Perl is open
source itself.

In fact, it is not difficult for suitably experienced hackers to produce a
modified Perl executable that makes it absolutely trivial for them to retrieve
the I<original> unencrypted source code with comments, whitespace and all (i.e.
not just a deparsed reconstruction of it).  One example that was mentioned in
the perl5-porters thread cited above is to modify the Perl executable to simply
print each line of the decrypted source stream that is fed to the parser, rather
than parsing and running it!

A typical hacker's opinion of all this is perhaps the following delightful
message that I received off-list during that perl5-porters thread from someone
who shall remain anonymous:

    "If you don't want anybody to see your source code, why don't you
    STICK IT UP YOUR ASS?!"
        -- Klortho

=head1 COMPATIBILITY

Before version 2.00 of this distribution, encrypted source code was simply the
raw output of the chosen encryption algorithm, which is typically "binary" data
and therefore susceptible to breakage caused by perl reading source files in
"text" mode, which has become the default on Windows since Perl 5.13.11
(specifically, perl change #270ca148cf).

As of version 2.00 of this distribution, each byte of encrypted source code is
now output as a pair of hexadecimal digits and therefore no longer susceptible
to such breakage.

B<THIS IS AN INCOMPATIBLE CHANGE.  CURRENT VERSIONS OF THESE MODULES WILL NOT BE
ABLE TO DECRYPT FILES ENCRYPTED WITH VERSIONS OF THESE MODULES PRIOR TO VERSION
2.00 OF THIS DISTRIBUTION, EVEN WHEN BUILT WITH THE SAME CONFIGURATION OPTIONS.
EXISTING ENCRYPTED FILES WILL NEED TO BE RE-ENCRYPTED.>

=head1 FEEDBACK

Patches, bug reports, suggestions or any other feedback is welcome.

Bugs can be reported on the CPAN Request Tracker at
F<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Filter-Crypto>.

Open bugs on the CPAN Request Tracker can be viewed at
F<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Filter-Crypto>.

Please test this distribution.  See CPAN Testers at F<http://testers.cpan.org/>
for details of how to get involved.

Previous test results on CPAN Testers can be viewed at
F<http://testers.cpan.org/search?request=dist&dist=Filter-Crypto>.

Please rate this distribution on CPAN Ratings at
F<http://cpanratings.perl.org/rate/?distribution=Filter-Crypto>.

=head1 SEE ALSO

B<crypt_file>;

L<Filter::Crypto::CryptFile>,
L<Filter::Crypto::Decrypt>,
L<PAR::Filter::Crypto>;

L<perlfilter>;
L<Filter::decrypt>;

L<PAR>;
L<PAR::Filter>.

In particular, the Filter::decrypt module (part of the "Filter" distribution)
contains a template for a Perl source code decryption filter on which the
Filter::Crypto::Decrypt module itself was based.

=head1 AVAILABILITY

The latest version of this module is available from CPAN (see
L<perlmodlib/"CPAN"> for details) at

F<http://www.cpan.org/authors/id/S/SH/SHAY/> or

F<http://www.cpan.org/modules/by-module/Filter/>.

=head1 INSTALLATION

See the F<INSTALL> file.

=head1 AUTHOR

Steve Hay E<lt>shay@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 2004-2010, 2012-2014 Steve Hay.  All rights reserved.

=head1 LICENCE

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself, i.e. under the terms of either the GNU General Public
License or the Artistic License, as specified in the F<LICENCE> file.

=head1 VERSION

Version 2.04

=head1 DATE

19 Feb 2014

=head1 HISTORY

See the F<Changes> file.

=cut

#===============================================================================
