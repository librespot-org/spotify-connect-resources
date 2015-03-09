package Log::Log4perl::JavaMap::NTEventLogAppender;

use Carp;
use strict;



sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    my ($source,   #        
        );

    if (defined $data->{Source}{value}) {
        $source = $data->{Source}{value}
    }elsif (defined $data->{source}{value}){
        $source = $data->{source}{value};
    }else{
        $source = 'user';
    }

    
    return Log::Log4perl::Appender->new("Log::Dispatch::Win32EventLog",
        name      => $appender_name,
        source    => $source,
        min_level => 'debug',
    );
}

1;

=head1 NAME

Log::Log4perl::JavaMap::NTEventLogAppender - wraps Log::Dispatch::Win32EventLog


=head1 DESCRIPTION

This maps log4j's NTEventLogAppender to Log::Dispatch::Win32EventLog

Possible config properties for log4j NTEventLogAppender are 

    Source

Possible config properties for Log::Dispatch::Win32EventLog are

    source

Boy, that was hard.

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2009 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
