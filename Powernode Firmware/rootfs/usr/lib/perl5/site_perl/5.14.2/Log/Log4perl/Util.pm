package Log::Log4perl::Util;

use File::Spec;

##################################################
sub module_available {  # Check if a module is available
##################################################
    my($full_name) = @_;

      # Weird cases like "strict;" (including the semicolon) would 
      # succeed with the eval below, so check those up front. 
      # I can't believe Perl doesn't have a proper way to check if a 
      # module is available or not!
    return 0 if $full_name =~ /[^\w:]/;

    local $SIG{__DIE__} = sub {};

    eval "require $full_name";

    if($@) {
        return 0;
    }

    return 1;
}

##################################################
sub tmpfile_name {  # File::Temp without the bells and whistles
##################################################

    my $name = File::Spec->catfile(File::Spec->tmpdir(), 
                              'l4p-tmpfile-' . 
                              "$$-" .
                              int(rand(9999999)));

        # Some crazy versions of File::Spec use backslashes on Win32
    $name =~ s#\\#/#g;
    return $name;
}

1;

__END__

=head1 NAME

Log::Log4perl::Util - Internal utility functions

=head1 DESCRIPTION

Only internal functions here. Don't peek.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2009 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
