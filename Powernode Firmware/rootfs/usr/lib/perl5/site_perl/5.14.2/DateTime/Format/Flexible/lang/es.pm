package DateTime::Format::Flexible::lang::es;

use strict;
use warnings;

sub new
{
    my ( $class , %params ) = @_;
    my $self = bless \%params , $class;
    return $self;
}

sub months
{
    # http://llts.stanford.edu/months.html
    # http://www.tarver-genealogy.net/aids/spanish/sp_dates_num.html#days
    return (
        qr{enero|enro|eno}i    => 1,
        qr{febr(?:ero)?|febo}i => 2,
        qr{marzo|mzo}i         => 3,
        qr{abr(?:il)?|abl}i    => 4,
        qr{\bmayo\b}i          => 5,
        qr{jun(?:io)?}i        => 6,
        qr{jul(?:io)?}i        => 7,
        qr{agosto|agto}i       => 8,
        qr{sept(?:iembre)}i    => 9,
        qr{septe|set}i         => 9,
        qr{oct(?:ubre)?}i      => 10,
        qr{nov(?:iembre)?}i    => 11,
        qr{novbre}i            => 11,
        qr{dic(?:iembre)?}i    => 12,
        qr{dice}i              => 12,
    );
}

sub days
{
    # http://www.tarver-genealogy.net/aids/spanish/sp_dates_num.html#days
    return (
        qr{\blunes\b}     => 1, # Monday
        qr{\bmartes\b}    => 2, # Tuesday
        qr{\bmiércoles\b} => 3, # Wednesday
        qr{\bjueves\b}    => 4, # Thursday
        qr{\bviernes\b}   => 5, # Friday
        qr{\bsábado\b}    => 6, # Saturday
        qr{\bdomingo\b}   => 7, # Sunday
    );
}

sub day_numbers
{
    # http://www.tarver-genealogy.net/aids/spanish/sp_dates_num.html#days
    return (
        qr{primero}                 => 1, # first
        qr{segundo}                 => 2, # second
        qr{tercero}                 => 3, # third
        qr{cuarto}                  => 4, # fourth
        qr{quinto}                  => 5, # fifth
        qr{sexto}                   => 6, # sixth
        qr{septimo}                 => 7, # seventh
        qr{octavo}                  => 8, # eighth
        qr{nono|noveno}             => 9, # ninth
        qr{decimo}                  => 10, # tenth
        qr{undecimo|decimoprimero}  => 11, # eleventh
        qr{duodecimo|decimosegundo} => 12, # twelfth
        qr{decimotercero}           => 13, # thirteenth
        qr{decimocuarto}            => 14, # fourteenth
        qr{decimoquinto}            => 15, # fifteenth
        qr{decimosexto}             => 16, # sixteenth
        qr{decimo\sseptimo}         => 17, # seventeenth
        qr{decimoctavo}             => 18, # eithteenth
        qr{decimonono}              => 19, # ninteenth
        qr{vigesimo}                => 20, # twentieth
        qr{vigesimo\sprimero}       => 21, # twenty first
        qr{vigesimo\ssegundo}       => 22, # twenty second
        qr{vigesimo\stercero}       => 23, # twenty third
        qr{vigesimo\scuarto}        => 24, # twenty fourth
        qr{veinticuatro}            => 24, # twenty four
        qr{vigesimo\squinto}        => 25, # twenty fifth
        qr{vigesimo\ssexto}         => 26, # twenty sixth
        qr{vigesimo\sseptimo}       => 27, # twenty seventh
        qr{vigesimo\soctavo}        => 28, # twenty eighth
        qr{vigesimo\snono}          => 29, # twenty ninth
        qr{trigesimo}               => 30, # thirtieth
        qr{trigesimo\sprimero}      => 31, # thirty first
    );
}

sub hours
{
    return (
        mediodia   => '12:00:00', # noon
        medianoche => '00:00:00', # midnight
    );
}

sub remove_strings
{
    return (
        qr{\bde\b}i, # remove ' de ' as in '29 de febrero de 1996'
    );
}

sub parse_time
{
    my ( $self, $date ) = @_;
    return $date;
}

sub string_dates
{
    my $base_dt = DateTime::Format::Flexible->base;
    return (
        ahora  => sub { return $base_dt->datetime },                                                   # now
        hoy    => sub { return $base_dt->clone->truncate( to => 'day' )->ymd } ,                       # today
        manana => sub { return $base_dt->clone->truncate( to => 'day' )->add( days => 1 )->ymd },      # tomorrow
        ayer   => sub { return $base_dt->clone->truncate( to => 'day' )->subtract( days => 1 )->ymd }, # yesterday
        'pasado manana' => sub { return DateTime->today->add( days => 2 )->ymd },                      # overmorrow (the day after tomorrow)
        epoca       => sub { return DateTime->from_epoch( epoch => 0 ) },
        '-infinito' => sub { return '-infinity' },
        infinito    => sub { return 'infinity'  },
    );
}

sub ago
{
    return qr{\bhace\b}i; # as in 3 years ago
}

sub math_strings
{
    return (
        ano     => 'years' ,
        anos    => 'years' ,
        'años'  => 'years' ,
        mes     => 'months' ,
        meses   => 'months' ,
        dia     => 'days' ,
        dias    => 'days' ,
        hora    => 'hours' ,
        horas   => 'hours' ,
        minuto  => 'minutes' ,
        minutos => 'minutes' ,
    );
}

sub timezone_map
{
    # http://home.tiscali.nl/~t876506/TZworld.html
    return (
        CET  => 'Europe/Madrid',
        CEST => 'Europe/Madrid',
        CST  => 'America/Cancun',
        CDT  => 'America/Cancun',
        MST  => 'America/Chihuahua',
        MDT  => 'America/Chihuahua',
        PST  => 'America/Tijuana',
        PDT  => 'America/Tijuana',
    );
}

1;
__END__

=encoding utf-8

=head1 NAME

DateTime::Format::Flexible::lang::es - spanish language plugin

=head1 DESCRIPTION

You should not need to use this module directly.

If you only want to use one language, specify the lang property when parsing a date.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     '29 de febrero de 1996' ,
     lang => ['es']
 );
 # $dt is now 1996-02-29T00:00:00

Note that this is not required, by default ALL languages are scanned when trying to parse a date.

=head2 new

Instantiate a new instance of this module.

=head2 months

month name regular expressions along with the month numbers (enero|enro|eno => 1)

=head2 days

day name regular expressions along the the day numbers (lunes => 1)

=head2 day_numbers

maps day of month names to the corresponding numbers (primero => 01)

=head2 hours

maps hour names to numbers (ediodia => 12:00:00)

=head2 remove_strings

strings to remove from the date (de as in cinco de mayo)

=head2 parse_time

currently does nothing

=head2 string_dates

maps string names to real dates (ahora => DateTime->now)

=head2 ago

the word use to denote a date in the past (Hace 3 años => 3 years ago)

=head2 math_strings

useful strings when doing datetime math

=head2 timezone_map

maps unofficial timezones to official timezones for this language (PDT  => America/Tijuana)

=head1 AUTHOR

    Tom Heady
    CPAN ID: thinc
    Punch, Inc.
    cpan@punch.net
    http://www.punch.net/

=head1 COPYRIGHT & LICENSE

Copyright 2011 Tom Heady.

This program is free software; you can redistribute it and/or
modify it under the terms of either:

=over 4

=item * the GNU General Public License as published by the Free
    Software Foundation; either version 1, or (at your option) any
    later version, or

=item * the Artistic License.

=back

=head1 SEE ALSO

F<DateTime::Format::Flexible>

=cut
