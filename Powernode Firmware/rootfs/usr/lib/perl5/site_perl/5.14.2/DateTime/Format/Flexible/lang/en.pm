package DateTime::Format::Flexible::lang::en;

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
        qr{Jan(?:uary)?}i        => 1,
        qr{Feb(?:ruary)?}i       => 2,
        qr{Mar(?:ch)?}i          => 3,
        qr{Apr(?:il)?}i          => 4,
        qr{May}i                 => 5,
        qr{Jun(?:e)?}i           => 6,
        qr{Jul(?:y)?}i           => 7,
        qr{Aug(?:ust)?}i         => 8,
        qr{Sep(?:t)?(?:ember)?}i => 9,
        qr{Oct(?:ober)?}i        => 10,
        qr{Nov(?:ember)?}i       => 11,
        qr{Dec(?:ember)?}i       => 12,
    );
}

sub days
{
    return (
        qr{\bMon(?:day)?\b}i    => 1,
        qr{\bTue(?:sday)?\b}i   => 2,
        qr{\bWed(?:nesday)?\b}i => 3,
        qr{\bThu(?:rsday)?\b}i  => 4,
        qr{\bFri(?:day)?\b}i    => 5,
        qr{\bSat(?:urday)?\b}i  => 6,
        qr{\bSun(?:day)?\b}i    => 7,
    );
}

sub day_numbers
{
    return (
        qr{first}            => 1,
        qr{second}           => 2,
        qr{third}            => 3,
        qr{fourth}           => 4,
        qr{fifth}            => 5,
        qr{sixth}            => 6,
        qr{seventh}          => 7,
        qr{eighth}           => 8,
        qr{ninth}            => 9,
        qr{tenth}            => 10,
        qr{eleventh}         => 11,
        qr{twelfth}          => 12,
        qr{thirteenth}       => 13,
        qr{fourteenth}       => 14,
        qr{fifteenth}        => 15,
        qr{sixteenth}        => 16,
        qr{seventeenth}      => 17,
        qr{eithteenth}       => 18,
        qr{ninteenth}        => 19,
        qr{twentieth}        => 20,
        qr{twenty\s?first}   => 21,
        qr{twenty\s?second}  => 22,
        qr{twenty\s?third}   => 23,
        qr{twenty\s?fourth}  => 24,
        qr{twenty\s?fifth}   => 25,
        qr{twenty\s?sixth}   => 26,
        qr{twenty\s?seventh} => 27,
        qr{twenty\s?eighth}  => 28,
        qr{twenty\s?ninth}   => 29,
        qr{thirtieth}        => 30,
        qr{thirty\s?first}   => 31,
    );
}

sub hours
{
    return (
        noon     => '12:00:00' ,
        midnight => '00:00:00' ,
    );
}

sub remove_strings
{
    return (
        qr{\bof\b}i,              # remove ' of ' as in '16th of November 2003'
        qr{(?:st|nd|rd|th)\b,?}i, # remove number extensions
        qr{\bnext\b}i,            # next sunday
    );
}

sub parse_time
{
    my ( $self, $date ) = @_;

    return $date if ( not $date =~ m{\s?at\s?}mx );
    my ( $pre, $time, $post ) = $date =~ m{\A(.+)\s?at\s?([\d\.:]+)(.+)?\z}mx;
    $post ||= q{};

    $date = $pre . 'T' . $time . 'T' . $post;
    return $date;
}

sub string_dates
{
    my $base_dt = DateTime::Format::Flexible->base;
    return (
        now         => sub { return $base_dt->datetime } ,
        today       => sub { return $base_dt->clone->truncate( to => 'day' )->ymd } ,
        tomorrow    => sub { return $base_dt->clone->truncate( to => 'day' )->add( days => 1 )->ymd },
        yesterday   => sub { return $base_dt->clone->truncate( to => 'day' )->subtract( days => 1 )->ymd },
        overmorrow  => sub { return $base_dt->clone->truncate( to => 'day' )->add( days => 2 )->ymd },
        allballs    => sub { return $base_dt->clone->truncate( to => 'day' ) },

        epoch       => sub { return DateTime->from_epoch( epoch => 0 ) },
        '-infinity' => sub { '-infinity' },
        infinity    => sub { 'infinity'  },
    );
}

sub ago
{
    return qr{\bago\b}; # as in 3 years ago
}

sub math_strings
{
    return (
        year   => 'years' ,
        years  => 'years' ,
        month  => 'months' ,
        months => 'months' ,
        day    => 'days' ,
        days   => 'days' ,
        hour   => 'hours' ,
        hours  => 'hours' ,
        minute => 'minutes' ,
        minutes => 'minutes' ,
    );
}

sub timezone_map
{
    # http://home.tiscali.nl/~t876506/TZworld.html
    return (
        EST => 'America/New_York',
        EDT => 'America/New_York',
        CST => 'America/Chicago',
        CDT => 'America/Chicago',
        MST => 'America/Denver',
        MDT => 'America/Denver',
        PST => 'America/Los_Angeles',
        PDT => 'America/Los_Angeles',
        AKST => 'America/Juneau',
        AKDT => 'America/Juneau',
        HAST => 'America/Adak',
        HADT => 'America/Adak',
        HST => 'Pacific/Honolulu',
    );
}

1;
__END__

=encoding utf-8

=head1 NAME

DateTime::Format::Flexible::lang::en - the english language plugin

=head1 DESCRIPTION

You should not need to use this module directly.

If you only want to use one language, specify the lang property when parsing a date.

example:

 my $dt = DateTime::Format::Flexible->parse_datetime(
     'Wed, Jun 10, 2009' ,
     lang => ['en']
 );
 # $dt is now 2009-06-10T00:00:00

Note that this is not required, by default ALL languages are scanned when trying to parse a date.

=head2 new

Instantiate a new instance of this module.

=head2 months

month name regular expressions along with the month numbers (Jan(?:uary)? => 1)

=head2 days

day name regular expressions along the the day numbers (Mon(?:day)? => 1)

=head2 day_numbers

maps day of month names to the corresponding numbers (first => 01)

=head2 hours

maps hour names to numbers (noon => 12:00:00)

=head2 remove_strings

strings to remove from the date (rd as in 3rd)

=head2 parse_time

searches for the string 'at' to help determine a time substring (sunday at 3:00)

=head2 string_dates

maps string names to real dates (now => DateTime->now)

=head2 ago

the word used to denote a date in the past (3 years ago)

=head2 math_strings

useful strings when doing datetime math

=head2 timezone_map

maps unofficial timezones to official timezones for this language (CST => America/Chicago)


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
