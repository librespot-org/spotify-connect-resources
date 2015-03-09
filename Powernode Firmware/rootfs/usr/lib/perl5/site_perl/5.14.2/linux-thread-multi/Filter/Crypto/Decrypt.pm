#===============================================================================
#
# Decrypt/lib/Filter/Crypto/Decrypt.pm
#
# DESCRIPTION
#   Module providing a Perl source code filter for running Perl files that have
#   been encrypted via Filter::Crypto::CryptFile.
#
# COPYRIGHT
#   Copyright (C) 2004-2009, 2012 Steve Hay.  All rights reserved.
#
# LICENCE
#   You may distribute under the terms of either the GNU General Public License
#   or the Artistic License, as specified in the LICENCE file.
#
#===============================================================================

package Filter::Crypto::Decrypt;

use 5.006000;

use strict;
use warnings;

use XSLoader qw();

#===============================================================================
# MODULE INITIALIZATION
#===============================================================================

our($VERSION);

BEGIN {
    $VERSION = '2.02';

    XSLoader::load(__PACKAGE__, $VERSION);
}

# Last error message.
our $ErrStr = '';

1;

__END__

#===============================================================================
# DOCUMENTATION
#===============================================================================

=head1 NAME

Filter::Crypto::Decrypt - Perl source code filter to run encrypted Perl files

=head1 SYNOPSIS

    use Filter::Crypto::Decrypt;

=head1 DESCRIPTION

This module provides a Perl source code decryption filter for running files that
have been encrypted via the
L<Filter::Crypto::CryptFile|Filter::Crypto::CryptFile> module.

You should rarely, if ever, need to touch this module.  The encrypted files
produced by the L<Filter::Crypto::CryptFile|Filter::Crypto::CryptFile> module
will automatically have the "C<use Filter::Crypto::Decrypt;>" statement added to
the start of them, which is all that is required to bring this decryption filter
into play.  See L<perlfilter> if you want to know more about how Perl source
code filters work.

=head1 DIAGNOSTICS

=head2 Warnings and Error Messages

This module may produce the following diagnostic messages.  They are classified
as follows (a la L<perldiag>):

    (W) A warning (optional).
    (F) A fatal error (trappable).
    (I) An internal error that you should never see (trappable).

=over 4

=item Can't add MAGIC to decryption filter's SV

(F) The SV used by the source code decryption filter to maintain state could not
be assigned MAGIC to have it automatically free up allocated memory when it is
destroyed.

=item Can't complete decryption: %s

(F) There was an error producing the final block of decrypted data.  The cipher
context structure used to perform the source code decryption could not be
finalized so the decryption could not be completed.  The last error message from
the decryption code is also given.

=item Can't continue decryption: %s

(F) There was an error reading or decrypting a block of data from the encrypted
Perl file.  The cipher context structure used to perform the source code
decryption could not be updated so the decryption could not continue.  The last
error message from the decryption code is also given.

=item Can't find MAGIC in decryption filter's SV

(F) The MAGIC assigned to the SV used by the source code decryption filter to
maintain state could not be found.

=item Can't run with DEBUGGING flags

(F) The encrypted Perl file is being run by a Perl with DEBUGGING flags enabled,
e.g. C<perl -Dp F<file>>.  This is not allowed since it may assist in retrieving
the original unencrypted source code.

=item Can't run with DEBUGGING Perl

(F) The encrypted Perl file is being run by a Perl that was built with DEBUGGING
enabled, i.e. C<-DDEBUGGING>.  This is not allowed since it may assist in
retrieving the original unencrypted source code.

=item Can't run with extra filters

(F) The encrypted Perl file is being run through extra source code filters (i.e.
over and above the decryption filter provided by this module).  This is not
allowed since it may assist in retrieving the original unencrypted source code.

=item Can't run with Perl compiler backend

(F) The encrypted Perl file is being run by a Perl with the Perl compiler
backend enabled, e.g. C<perl -MO=Deparse F<file>>.  This is not allowed since it
may assist in retrieving the original unencrypted source code.

=item Can't run with Perl debugger

(F) The encrypted Perl file is being run by a Perl with the Perl debugger
enabled, e.g. C<perl -d:ptkdb F<file>>.  This is not allowed since it may assist
in retrieving the original unencrypted source code.

=item Can't start decryption: %s

(F) The cipher context structure used to perform the source code decryption
could not be initialized so the decryption could not be started.  The last error
message from the decryption code is also given.

=item Found wrong MAGIC in decryption filter's SV: No valid mg_ptr

(F) The MAGIC found in the SV used by the source code decryption filter to
maintain state was not the correct MAGIC since it did not contain a valid
C<mg_ptr> member.

=item Found wrong MAGIC in decryption filter's SV: Wrong mg_ptr "signature"

(F) The MAGIC found in the SV used by the source code decryption filter to
maintain state was not the correct MAGIC since it did not contain the correct
"signature" in its C<mg_ptr> member.

=item No such package '%s'

(F) This module's bootstrap function was called on the specified package, which
does not exist.

=item Unknown crypto context mode '%d'

(I) The crypto context structure used internally when performing decryption has
been set-up with a crypt mode that it does not recognize.

=back

=head1 EXPORTS

I<None>.

=head1 KNOWN BUGS

I<None>.

=head1 SEE ALSO

L<Filter::Crypto>;

L<Filter::CBC>, L<Crypt::License>.

The latter two modules (in separate CPAN distributions, not related to the
Filter-Crypto distribution in any way) are both Perl-level source code filters
and are thus even less secure than this module is.  (This module's filter code
is written in XS and C.)

=head1 ACKNOWLEDGEMENTS

Much of the XS code is based on that in the Filter::decrypt module (version
1.04), written by Paul Marquess.

Thanks to Nick Ing-Simmons for help in getting the MAGIC attached to the
decryption filter's SV working.

=head1 AUTHOR

Steve Hay E<lt>shay@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 2004-2009, 2012-2013 Steve Hay.  All rights reserved.

=head1 LICENCE

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself, i.e. under the terms of either the GNU General Public
License or the Artistic License, as specified in the F<LICENCE> file.

=head1 VERSION

Version 2.02

=head1 DATE

14 Feb 2013

=head1 HISTORY

See the F<Changes> file.

=cut

#===============================================================================
