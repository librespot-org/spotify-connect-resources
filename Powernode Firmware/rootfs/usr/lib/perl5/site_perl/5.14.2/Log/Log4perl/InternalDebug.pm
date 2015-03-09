package Log::Log4perl::InternalDebug;
use warnings;
use strict;

use File::Temp qw(tempfile);
use File::Spec;

require Log::Log4perl::Resurrector;

###########################################
sub enable {
###########################################
    unshift @INC, \&internal_debug_loader;
}

##################################################
sub internal_debug_fh {
##################################################
    my($file) = @_;

    local($/) = undef;
    open FILE, "<$file" or die "Cannot open $file";
    my $text = <FILE>;
    close FILE;

    my($tmp_fh, $tmpfile) = tempfile( UNLINK => 1 );

    $text =~ s/_INTERNAL_DEBUG(?!\s*=>)/1/g;

    print $tmp_fh $text;
    seek $tmp_fh, 0, 0;

    return $tmp_fh;
}

###########################################
sub internal_debug_loader {
###########################################
    my ($code, $module) = @_;

      # Skip non-Log4perl modules
    if($module !~ m#^Log/Log4perl#) {
        return undef;
    }

    my $path = $module;
    if(!-f $path) {
        $path = Log::Log4perl::Resurrector::pm_search( $module );
    }

    my $fh = internal_debug_fh($path);

    my $abs_path = File::Spec->rel2abs( $path );
    $INC{$module} = $abs_path;

    return $fh;
}

###########################################
sub resurrector_init {
###########################################
    unshift @INC, \&resurrector_loader;
}

###########################################
sub import {
###########################################
    # enable it on import
  enable();
}

1;

__END__

=head1 NAME

Log::Log4perl::InternalDebug - Dark Magic to enable _INTERNAL_DEBUG

=head1 DESCRIPTION

When called with

    perl -MLog::Log4perl::InternalDebug t/001Test.t

scripts will run with _INTERNAL_DEBUG set to a true value and hence
print internal Log4perl debugging information.

=head1 COPYRIGHT AND LICENSE

Copyright 2010 by Mike Schilli E<lt>m@perlmeister.comE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
