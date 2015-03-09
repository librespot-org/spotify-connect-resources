package Log::Log4perl::Layout;


use Log::Log4perl::Layout::SimpleLayout;
use Log::Log4perl::Layout::PatternLayout;
use Log::Log4perl::Layout::PatternLayout::Multiline;


####################################################
sub appender_name {
####################################################
    my ($self, $arg) = @_;

    if ($arg) {
        die "setting appender_name unimplemented until it makes sense";
    }
    return $self->{appender_name};
}


##################################################
sub define {
##################################################
    ;  #subclasses may implement
}


##################################################
sub render {
##################################################
    die "subclass must implement render";
}

1;

__END__

=head1 NAME

Log::Log4perl::Layout - Log4perl Layout Virtual Base Class

=head1 SYNOPSIS

    # Not to be used directly, see below

=head1 DESCRIPTION

C<Log::Log4perl::Layout> is a virtual base class for the two currently 
implemented layout types

    Log::Log4perl::Layout::SimpleLayout
    Log::Log4perl::Layout::PatternLayout

Unless you're implementing a new layout class for Log4perl, you shouldn't
use this class directly, but rather refer to
L<Log::Log4perl::Layout::SimpleLayout> or 
L<Log::Log4perl::Layout::PatternLayout>.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2009 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
