#===============================================================================
#
# lib/PAR/Filter/Crypto.pm
#
# DESCRIPTION
#   PAR::Filter sub-class providing the means to convert files to an encrypted
#   state in which they can be run via Filter::Crypto::Decrypt, primarily for
#   use in creating PAR archives in which the Perl files are encrypted.
#
# COPYRIGHT
#   Copyright (C) 2004-2008, 2012 Steve Hay.  All rights reserved.
#
# LICENCE
#   You may distribute under the terms of either the GNU General Public License
#   or the Artistic License, as specified in the LICENCE file.
#
#===============================================================================

package PAR::Filter::Crypto;

use 5.006000;

use strict;
use warnings;

use Carp qw(carp croak);
use Fcntl qw(:seek);
use File::Temp qw(tempfile);
use Filter::Crypto::CryptFile qw(:DEFAULT $ErrStr);
use PAR::Filter qw();

#===============================================================================
# CLASS INITIALIZATION
#===============================================================================

our(@ISA, $VERSION);

BEGIN {
    @ISA = qw(PAR::Filter);

    $VERSION = '1.07';
}

#===============================================================================
# PUBLIC API
#===============================================================================

# This method is based on the apply() method in the PAR::Filter::Bytecode module
# in the PAR distribution (version 0.85).

sub apply {
    my($class, $ref, $filename, $name) = @_;

    # If we're encrypting modules (e.g. pp -F Crypto ...) then be careful not to
    # encrypt the decryption module.
    return 1 if $filename eq 'Filter/Crypto/Decrypt.pm';

    if (eval { require Module::ScanDeps; 1 } and
        $Module::ScanDeps::VERSION eq '0.75')
    {
        carp('Detected Module::ScanDeps version 0.75, which may not work ' .
             'correctly with ' . __PACKAGE__);
    }

    # Open a temporary file.  (The temporary file will be deleted automatically
    # since tempfile() is called in scalar context.)
    my $fh = tempfile();

    # Write the source code to be encrypted to the temporary filehandle.
    print $fh $$ref;

    # Rewind the filehandle so that the encryption knows where to begin.
    seek $fh, 0, SEEK_SET or
        croak("Can't rewind temporary filehandle before encryption: $!");

    # Encrypt the source code.
    crypt_file($fh, CRYPT_MODE_ENCRYPT) or
        croak("crypt_file() failed: $ErrStr");

    # Rewind the filehandle again and read the now-encrypted source code from it
    # back into the scalar referred to by $ref.
    seek $fh, 0, SEEK_SET or
        croak("Can't rewind temporary filehandle after encryption: $!");

    {
        local $/;
        $$ref = <$fh>;
    }

    close $fh or
        carp("Can't close temporary filehandle after encryption: $!");

    return 1;
}

1;

__END__

#===============================================================================
# DOCUMENTATION
#===============================================================================

=head1 NAME

PAR::Filter::Crypto - Encrypt Perl files in PAR archives

=head1 SYNOPSIS

    # Create a PAR archive containing an encrypted Perl script:
    $ pp -f Crypto -M Filter::Crypto::Decrypt -o hello hello.pl

    # The same, but with included modules encrypted as well:
    $ pp -f Crypto -F Crypto -M Filter::Crypto::Decrypt -o hello hello.pl

    # Encrypt Perl source code in $code:
    use PAR::Filter::Crypto;
    PAR::Filter::Crypto->apply(\$code);

=head1 DESCRIPTION

This module is a L<PAR::Filter|PAR::Filter> sub-class for producing PAR archives
containing encrypted Perl files.  The PAR::Filter class itself is part of the
L<PAR|PAR> distribution, and is clearly a prerequisite for using this sub-class.

The usual means of producing a PAR archive is using the B<pp> script, which also
comes with the PAR distribution.  That script's B<-f> and B<-F> command-line
options can be used to specify a "filter" through which to pass the Perl files
being put into the PAR archive.  Specifying this sub-class as the filter (i.e.
"B<-f Crypto>" for scripts and/or "B<-F Crypto>" for modules) means that the
Perl files will be encrypted using the
L<Filter::Crypto::CryptFile|Filter::Crypto::CryptFile> module.  The resulting
encrypted files are what will be placed in the PAR archive.

Note that the encrypted script requires the
L<Filter::Crypto::Decrypt|Filter::Crypto::Decrypt> module in order to decrypt
itself when it is run.  The original Perl script will not have specified any
such dependency, so B<pp> will not automatically include that module in the PAR
archive for you.  Therefore, you must use the B<-M> option to force that module
to be included.  Also note that if you use the B<-F> option to encrypt modules
as well then the filtering will automatically skip the
L<Filter::Crypto::Decrypt|Filter::Crypto::Decrypt> module itself for obvious
reasons.  A typical B<pp> invocation is thus something like:

    $ pp -f Crypto -F Crypto -M Filter::Crypto::Decrypt -o hello hello.pl

(Version 0.75 of the L<Module::ScanDeps|Module::ScanDeps> module, used by B<pp>
to scan for dependencies that need including in the PAR archive, is known to
have problems finding shared library files for modules specified by B<pp>'s
B<-M> option (as illustrated above).  If you find that the shared library file
for Filter::Crypto::Decrypt is missing from your PAR archive then you need to
upgrade Module::ScanDeps to version 0.76 or higher.)

Of course, you must not include the Filter::Crypto::CryptFile module as well,
otherwise people to whom you distribute your PAR archive will have the means to
easily decrypt the encrypted Perl script within it!

Also, note that the script is encrypted by reading its entire contents into
memory, encrypting it in memory, and then writing it out to disk.  This should
be safe for most purposes given that Perl scripts are typically not very large,
but other methods should be considered instead if this is likely to cause
out-of-memory errors due to the size of the scripts, e.g. if the scripts have
very large C<__DATA__> sections.

=head2 Methods

=over 4

=item C<apply($ref)>

Class method.  Encrypts the Perl source code referred to by $ref, and replaces
the code referred to by $ref with the encrypted code.  Thus, the code in $$ref
gets encrypted "in-place".

Returns 1 on success, or C<croak()>s on failure (since the usual caller,
PAR::Filter::apply(), does not bother checking the return value (as of
PAR::Filter version 0.02, at least)).

=back

=head1 DIAGNOSTICS

=head2 Warnings and Error Messages

This module may produce the following diagnostic messages.  They are classified
as follows (a la L<perldiag>):

    (W) A warning (optional).
    (F) A fatal error (trappable).
    (I) An internal error that you should never see (trappable).

=over 4

=item Can't close temporary filehandle after encryption: %s

(W) The temporary file used to perform the encryption could not be closed after
use.  The system error message corresponding to the standard C library C<errno>
variable is also given.

=item Can't rewind temporary filehandle before encryption: %s

(F) The temporary file used to perform the encryption could not be rewound
before encrypting the source that was just written to it.  The system error
message corresponding to the standard C library C<errno> variable is also given.

=item Can't rewind temporary filehandle after encryption: %s

(F) The temporary file used to perform the encryption could not be rewound after
encrypting the source code that was written to it.  The system error message
corresponding to the standard C library C<errno> variable is also given.

=item crypt_file() failed: %s

(F) The C<crypt_file()> function from the Filter::Crypto::CryptFile module that
is used to perform the encryption failed.  The last error message from the
Filter::Crypto::CryptFile module is also given.

=item Detected Module::ScanDeps version 0.75, which may not work correctly with
      PAR::Filter::Crypto

(W) Your current installation of the Module::ScanDeps module, used by B<pp> to
scan for dependencies that need including in the PAR archive, was found to be
version 0.75, which is known to have problems finding shared library files for
modules specified by B<pp>'s B<-M> option.  If you are running B<pp> with the
B<-M> option and find that the shared library file for Filter::Crypto::Decrypt
is missing from your PAR archive then you need to upgrade Module::ScanDeps to
version 0.76 or higher.

=back

=head1 EXPORTS

I<None>.

=head1 KNOWN BUGS

I<None>.

=head1 SEE ALSO

L<PAR::Filter>;

L<Filter::Crypto>.

=head1 ACKNOWLEDGEMENTS

The C<apply()> method is based on that in the PAR::Filter::Bytecode module in
the PAR distribution (version 0.85), written by Autrijus Tang.

=head1 AUTHOR

Steve Hay E<lt>shay@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (C) 2004-2008, 2012 Steve Hay.  All rights reserved.

=head1 LICENCE

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself, i.e. under the terms of either the GNU General Public
License or the Artistic License, as specified in the F<LICENCE> file.

=head1 VERSION

Version 1.07

=head1 DATE

02 Mar 2012

=head1 HISTORY

See the F<Changes> file.

=cut

#===============================================================================
