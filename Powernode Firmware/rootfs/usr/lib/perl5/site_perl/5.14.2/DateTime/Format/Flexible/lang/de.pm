package DateTime::Format::Flexible::lang::de;

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
    return (
        qr{Jan(?:uar)?}i        => 1,
        qr{Jän(?:er)?}i         => 1, # Austrian?!
        qr{Feb(?:ruar)?}i       => 2,
        qr{Mär(?:z)?|Maerz}i    => 3,
        qr{Apr(?:il)?}i         => 4,
        qr{Mai}i                => 5,
        qr{Jun(?:i)?}i          => 6,
        qr{Jul(?:i)?}i          => 7,
        qr{Aug(?:ust)?}i        => 8,
        qr{Sep(?:tember)?}i     => 9,
        qr{Okt(?:ober)?}i       => 10,
        qr{Nov(?:ember)?}i      => 11,
        qr{Dez(?:ember)?}i      => 12,
    );
}

sub days
{
    return (
        qr{\bMo(?:ntag)?\b}i     => 1, # Monday
        qr{\bDi(?:enstag)?\b}i   => 2, # Tuesday
        qr{\bMi(?:ttwoch)?\b}i   => 3, # Wednesday
        qr{\bDo(?:nnerstag)?\b}i => 4, # Thursday
        qr{\bFr(?:eitag)?\b}i    => 5, # Friday
        qr{\bSa(?:mstag)?\b}i    => 6, # Saturday
        qr{\bSonnabend\b}i       => 6, # Saturday
        qr{\bSo(?:nntag)?\b}i    => 7, # Sunday
    );
}

sub day_numbers
{
    return (
        qr{erster}i               => 1, # first
        qr{ersten}i               => 1, # first
        qr{zweiter}i              => 2, # second
        qr{dritter}i              => 3, # third
        qr{vierter}i              => 4, # fourth
        qr{fünfter}i              => 5, # fifth
        qr{fuenfter}i             => 5, # fifth
        qr{sechster}i             => 6, # sixth
        qr{siebter}i              => 7, # seventh
        qr{achter}i               => 8, # eighth
        qr{neunter}i              => 9, # ninth
        qr{zehnter}i              => 10, # tenth
        qr{elfter}i               => 11, # eleventh
        qr{zwölfter}i             => 12, # twelfth
        qr{zwoelfter}i            => 12, # twelfth
        qr{dreizehnter}i          => 13, # thirteenth
        qr{vierzehnter}i          => 14, # fourteenth
        qr{vierzehnten}i          => 14, # fourteenth
        qr{fünfzehnter}i          => 15, # fifteenth
        qr{fuenfzehnter}i         => 15, # fifteenth
        qr{sechzehnter}i          => 16, # sixteenth
        qr{siebzehnter}i          => 17, # seventeenth
        qr{achtzehnter}i          => 18, # eithteenth
        qr{neunzehnter}i          => 19, # ninteenth
        qr{zwanzigster}i          => 20, # twentieth
        qr{einundzwanzigster}i    => 21, # twenty first
        qr{zweiundzwanzigster}i   => 22, # twenty second
        qr{dreiundzwanzigster}i   => 23, # twenty third
        qr{vierundzwanzigster}i   => 24, # twenty fourth
        qr{fünfundzwanzigster}i   => 25, # twenty fifth
        qr{fuenfundzwanzigster}i  => 25, # twenty fifth
        qr{sechsundzwanzigster}i  => 26, # twenty sixth
        qr{siebenundzwanzigster}i => 27, # twenty seventh
        qr{achtundzwanzigster}i   => 28, # twenty eighth
        qr{neunundzwanzigster}i   => 29, # twenty ninth
        qr{dreißigster}i          => 30, # thirtieth
        qr{dreissigster}i         => 30, # thirtieth
        qr{einunddreißigster}i    => 31, # thirty first
        qr{einunddreissigster}i   => 31, # thirty first
    );
}

sub hours
{
    return (
        Mittag       => '12:00:00', # noon
        mittags      => '12:00:00', # noon
        Mitternacht  => '00:00:00', # midnight
        mitternachts => '00:00:00', # midnight
    );
}

sub remove_strings
{
    return (
        # we want to remove ' am ' only when it does not follow a digit
        # if we just remove ' am ', it removes am/pm designation, losing accuracy
        qr{(?<!\d)\sam\b}i, # remove ' am ' as in '20. Feb am Mittag'
        # we can also remove it if it is at the beginning
        qr{\A\bam\b}i,
        qr{\bum\b}i,        # remove ' um ' as in '20. Feb um Mitternacht'
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
        jetzt   => sub { return $base_dt->datetime },                                                   # now
        heute   => sub { return $base_dt->clone->truncate( to => 'day' )->ymd } ,                       # today
        morgen  => sub { return $base_dt->clone->truncate( to => 'day' )->add( days => 1 )->ymd },      # tomorrow
        gestern => sub { return $base_dt->clone->truncate( to => 'day' )->subtract( days => 1 )->ymd }, # yesterday
        'übermorgen' => sub { return DateTime->today->add( days => 2 )->ymd },  # overmorrow (the day after tomorrow) don't know if the Umlaut works
        uebermorgen  => sub { return DateTime->today->add( days => 2 )->ymd },   # overmorrow (the day after tomorrow)
        Epoche       => sub { return DateTime->from_epoch( epoch => 0 ) },
        '-unendlich' => sub { return '-infinity' },
        unendlich    => sub { return 'infinity'  },
    );
}

sub ago
{
    return qr{\bvor\b}; # as in 3 years ago
}

sub math_strings
{
    return (
        Jahr    => 'years' ,
        Jahre   => 'years' ,
        Jahren  => 'years' ,
        Monat   => 'months' ,
        Monate  => 'months' ,
        Tag     => 'days' ,
        Tage    => 'days' ,
        Stunde  => 'hours' ,
        Stunden => 'hours' ,
        Minute  => 'minutes' ,
        Minuten => 'minutes' ,
    );
}

sub timezone_map
{
    # http://home.tiscali.nl/~t876506/TZworld.html
    return (
        CET  => 'Europe/Berlin',
        CEST => 'Europe/Berlin',
        MEZ  => 'Europe/Berlin', # German Version: Mitteleuropäische Zeit
        MESZ => 'Europe/Berlin', # Mitteleuropäische Sommerzeit
    );
}

1;
__END__

=encoding utf-8

=head1 NAME

DateTime::Format::Flexible::lang::de - german language plugin

=head1 DESCRIPTION

You should not need to use this module directly.

If you only want to use one language, specify the lang property when parsing a date.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     'Montag, 6. Dez 2010' ,
     lang => ['de']
 );
 # $dt is now 2010-12-06T00:00:00

Note that this is not required, by default ALL languages are scanned when trying to parse a date.

=head2 new

Instantiate a new instance of this module.

=head2 months

month name regular expressions along with the month numbers (Jan(:?uar)? => 1)

=head2 days

day name regular expressions along the the day numbers (Montag => 1)

=head2 day_numbers

maps day of month names to the corresponding numbers (erster => 01)

=head2 hours

maps hour names to numbers (Mittag => 12:00:00)

=head2 remove_strings

strings to remove from the date (um as in um Mitternacht)

=head2 parse_time

currently does nothing

=head2 string_dates

maps string names to real dates (jetzt => DateTime->now)

=head2 ago

the word use to denote a date in the past (vor 3 Jahren => 3 years ago)

=head2 math_strings

useful strings when doing datetime math

=head2 timezone_map

maps unofficial timezones to official timezones for this language (MEZ => Europe/Berlin)

=head1 AUTHOR

    Mark Trettin <nulldevice.mark@gmx.de>

    Based on DateTime::Format::Flexible::lang::en by
    Tom Heady
    CPAN ID: thinc
    Punch, Inc.
    cpan@punch.net
    http://www.punch.net/

=head1 COPYRIGHT & LICENSE

Copyright 2011 Mark Trettin.

This program is free software; you can redistribute it and/or
modify it under the terms of either:

=over 4

=item * the GNU General Public License as published by the Free
    Software Foundation; either version 1, or (at your option) any
    later version, or

=item * the Artistic License version.

=back

=head1 SEE ALSO

F<DateTime::Format::Flexible>

=cut
### Local variables:
### coding: utf-8
### End:
