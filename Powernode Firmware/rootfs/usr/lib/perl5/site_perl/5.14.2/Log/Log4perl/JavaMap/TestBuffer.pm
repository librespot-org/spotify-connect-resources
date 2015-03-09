package Log::Log4perl::JavaMap::TestBuffer;

use Carp;
use strict;
use Log::Log4perl::Appender::TestBuffer;

use constant _INTERNAL_DEBUG => 0;

sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    return Log::Log4perl::Appender->new("Log::Log4perl::Appender::TestBuffer",
                                        name => $appender_name);
}

1;

=head1 NAME

Log::Log4perl::JavaMap::TestBuffer - wraps Log::Log4perl::Appender::TestBuffer

=head1 SYNOPSIS

=head1 DESCRIPTION

Just for testing the Java mapping.

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Dispatch::Screen

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2009 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
