##################################################
package Log::Log4perl::Layout::NoopLayout;
##################################################


##################################################
sub new {
##################################################
    my $class = shift;
    $class = ref ($class) || $class;

    my $self = {
        format      => undef,
        info_needed => {},
        stack       => [],
    };

    bless $self, $class;

    return $self;
}

##################################################
sub render {
##################################################
    #my($self, $message, $category, $priority, $caller_level) = @_;
    return $_[1];;
}

1;

__END__

=head1 NAME

Log::Log4perl::Layout::NoopLayout - Pass-thru Layout

=head1 SYNOPSIS

  use Log::Log4perl::Layout::NoopLayout;
  my $layout = Log::Log4perl::Layout::NoopLayout->new();

=head1 DESCRIPTION

This is a no-op layout, returns the logging message unaltered,
useful for implementing the DBI logger.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2009 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
