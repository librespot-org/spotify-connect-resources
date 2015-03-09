package DateTimeX::Easy;
BEGIN {
  $DateTimeX::Easy::VERSION = '0.089';
}
# ABSTRACT: Parse a date/time string using the best method available

use warnings;
use strict;

use constant DEBUG => 0;


use base qw/Exporter/;
our @EXPORT_OK = qw/datetime parse parse_datetime parse_date new_datetime new_date date/;

use DateTime;
use DateTime::Format::Natural;
use DateTime::Format::Flexible;
# use DateTime::Format::DateParse; # Unfortunately, not as useful to use because of that default "local" time zone business.
use DateTimeX::Easy::DateParse; # Using this instead, hrm.
use Scalar::Util qw/blessed/;
use Carp;

my $have_ICal;
eval {
    require DateTime::Format::ICal;
    $have_ICal = 1;
};

my $have_DateManip;
eval {
    require DateTime::Format::DateManip;
    $have_DateManip = 1;
};
my $natural_parser = DateTime::Format::Natural->new;

my %_truncate_range = qw/
    month year
    day month
    hour day
    minute hour
    second minute
    nanosecond second
/;
my %_delta_range = (
    month => [qw/years months/],
    day => [qw/months days/],
    hour => [qw/days hours/],
    minute => [qw/hours minutes/],
    second => [qw/minutes seconds/],
);
my %_first_or_last = qw/
    first       first
    last        last
    begin       first
    beginning   first
    start       first
    end         last
    ending      last
/;

my @_parser_order = qw/
    Flexible
    DateParse
    Natural
/;
unshift @_parser_order, qw/ICal/ if $have_ICal;
push @_parser_order, qw/DateManip/ if $have_DateManip;
my %_parser_source = (
    ICal => sub {
        return DateTime::Format::ICal->parse_datetime(shift);
    },

    DateParse => sub {
        return DateTimeX::Easy::DateParse->parse_datetime(shift);
    },
    
    Natural => sub {
        local $SIG{__WARN__} = sub {}; # Make sure ::Natural/Date::Calc stay quiet... don't really like this, oh well...
        my $dt = $natural_parser->parse_datetime(shift);
        return unless $natural_parser->success;
        return $dt;
    },

    Flexible => sub {
        my $parse = shift;
        my $time_zone;
        # First, try to extract out any timezone information
        {
            ##################################################
            # 2008-09-16 13:23:57 Eastern Daylight (?:Time)? #
            ##################################################
            if ($parse =~ s/\s+(?:(Eastern|Central|Mountain|Pacific)\s+(?:Daylight|Standard)(?:\s+Time)?).*$//) {
                $time_zone = "US/$1";
            }
            ##################################
            # 2008-09-16 13:23:57 US/Eastern #
            ##################################
            elsif ($parse =~ s/\s+([A-Za-z][A-Za-z0-9\/\._]*)\s*$//) { # Look for a timezone-like string at the end of $parse
                $time_zone = $1;
                $parse = "$parse $time_zone" and undef $time_zone if $time_zone && $time_zone =~ m/^[ap]\.?m\.?$/i; # Put back AM/PM if we accidentally slurped it out
            }
            #########################################################
            # 2008-09-16 13:23:57 Eastern Daylight Time (GMT+05:00) #
            #########################################################
            elsif ($parse =~ s/(?:\s+[A-Z]\w+)*\s+\(?(?:GMT|UTC)?([-+]\d{2}:\d{2})\)?\s*$//) {
                $time_zone = $1;
            }
# Flexible can't seem to parse (GMT+0:500)
#            elsif ($parse =~ s/(?:\s+[A-Z]\w+)*(\s+\(GMT[-+]\d{2}:\d{2}\)\s*)$//) {
#                $parse = "$parse $1";
#            }
            #############################
            # 2008-09-16 13:23:57 +0500 #
            #############################
            elsif ($parse =~ s/\s+([-+]\d{3,})\s*$//) {
                $time_zone = $1;
            }
        }
        return unless my $dt = DateTime::Format::Flexible->build($parse);
        if ($time_zone) {
            $dt->set_time_zone("floating");
            $dt->set_time_zone($time_zone);
        }
        return $dt;
    },

    DateManip => sub {
        return DateTime::Format::DateManip->parse_datetime(shift);
    },
);

sub new {
    shift if $_[0] && $_[0] eq __PACKAGE__;

    my $parse;
    $parse = shift if @_ % 2;

    my %in = @_;
    $parse = delete $in{parse} if exists $in{parse};
    my $truncate = delete $in{truncate};
    my $soft_time_zone_conversion = delete $in{soft_time_zone_conversion};
    my $time_zone_if_floating = delete $in{default_time_zone};
    $time_zone_if_floating = delete $in{time_zone_if_floating} if exists $in{time_zone_if_floating};
    my $parser_order = delete $in{parser_order};
    my $parser_exclude = delete $in{parser_exclude};
    my $ambiguous = 1;
    $ambiguous = delete $in{ambiguous} if exists $in{ambiguous};

    my ($time_zone);
    $time_zone = delete $in{tz} if exists $in{tz};
    $time_zone = delete $in{timezone} if exists $in{timezone};
    $time_zone = delete $in{time_zone} if exists $in{time_zone}; # "time_zone" takes precedence over "timezone"

    my @delta;

    my $original_parse = $parse;
    my $parse_dt;
    if ($parse) {
        if (blessed $parse && $parse->isa("DateTime")) { # We have a DateTime object as $parse
            $parse_dt = $parse;
        }
        else {

            if (1) {
                my $got_ambiguous;
                my ($last_delta);
                while ($parse =~ s/^\s*(start|first|last|(?:begin|end)(?:ning)?)\s+(year|month|day|hour|minute|second)\s+of\s+//i) {
                    my $first_or_last = $1;
                    $first_or_last = $_first_or_last{lc $first_or_last};
                    my $period = $2;
                    $last_delta->{add} = [ "${period}s" => 1 ] if $last_delta;
                    push @delta, $last_delta = my $delta = { period => $period };
                    if ($first_or_last ne "first") {
                        $delta->{last} = 1;
                        $delta->{subtract} = [ "${period}s" => 1 ];
                    }
                    else {
                        $delta->{first} = 1;
                    }
                }
                my $last_parse = $parse;
                my $period;
                if ($parse =~ s/^\s*(start|this|next|first|last|(?:begin|end)(?:ning)?)\s+(year|month|day|hour|minute|second)(?:\s+of\s+)?//) {
                    $period = $2;
                    $last_delta->{add} = [ "${period}s" => 1 ] if $last_delta && $last_delta->{last};
                    push @delta, { truncate => $period};
                    $parse = $last_parse unless $parse;
                }
                elsif ($parse =~ s/^\s*(year|month|day|hour|minute|second)\s+of\s+//i) {
                    $period = $1;
                    $last_delta->{add} = [ "${period}s" => 1 ] if $last_delta && $last_delta->{last};
                    push @delta, { truncate => $period };
                }
                elsif (@delta) {
                    $got_ambiguous = 1;
                    $period = $last_delta->{period};
                    my $truncate = $_truncate_range{$period};
                    push @delta, my $delta = { truncate => $truncate };
                    my $delta_range = $_delta_range{$period};
                    if ($delta_range) {
                        my ($add, $subtract) = @$delta_range;
                        if ($last_delta->{last}) {
                            $last_delta->{add} = [ "${add}" => 1 ];
                        }
                    }
                }

                croak "Can't parse \"$original_parse\" since it's too ambiguous" if $got_ambiguous && ! $ambiguous;
            }

            my @parser_order = $parser_order ? (ref $parser_order eq "ARRAY" ? @$parser_order : ($parser_order)) : @_parser_order;
            my (%parser_exclude);
            %parser_exclude = map { $_ => 1 } (ref $parser_exclude eq "ARRAY" ? @$parser_exclude : ($parser_exclude)) if $parser_exclude;
            my %parser_source = %_parser_source;
            if (DEBUG) {
                warn "Parse $parse\n";
            }
            # TODO Kinda hackish
            if ($parse =~ m/^[1-9]\d{3}$/) { # If it's a four digit year... yeah, arbitrary
                $parse_dt = DateTime->new(year => $parse);
            }
            while (! $parse_dt && @parser_order) {
                my $parser = shift @parser_order;
                next if $parser_exclude{$parser};
                # warn "Try $parser:\n" if DEBUG;
                my $parser_code = $parser_source{$parser};
                eval {
                    $parse_dt = $parser_code->($parse);
                };
                if (DEBUG) {
                    if ($@) {
                        warn "FAIL $parser: $@\n";
                    }
                    elsif ($parse_dt) {
                        warn "PASS $parser: $parse_dt\n"; 
                    }
                    else {
                        warn "FAIL $parser\n";
                    }
                }
                undef $parse_dt if $@;
            }
        }
        return unless $parse_dt;
    }

    my %DateTime;
    $DateTime{time_zone} = "floating";
    if ($parse_dt) {
        $DateTime{$_} = $parse_dt->$_ for qw/year month day hour minute second nanosecond time_zone/;
    }
    @DateTime{keys %in} = values %in;
    
    return unless my $dt = DateTime->new(%DateTime);

    if ($time_zone) {
        if ($soft_time_zone_conversion) {
            $dt->set_time_zone("floating");
        }
        $dt->set_time_zone($time_zone);
    }
    elsif ($time_zone_if_floating && $dt->time_zone->is_floating) {
        $dt->set_time_zone($time_zone_if_floating);
    }

    if ($truncate) {
        $truncate = $truncate->[1] if ref $truncate eq "ARRAY";
        $truncate = (values %$truncate)[0] if ref $truncate eq "HASH";
        $dt->truncate(to => $truncate);
    }
    elsif (@delta) {
        if (DEBUG) {
            require YAML;
            warn "$original_parse => $parse => $dt";
        }
        for my $delta (reverse @delta) {
            warn YAML::Dump($delta) if DEBUG;
            if ($delta->{truncate}) {
                $dt->truncate(to => $delta->{truncate});
            }
            else {
                $dt->add(@{ $delta->{add} }) if $delta->{add};
                $dt->subtract(@{ $delta->{subtract} }) if $delta->{subtract};
            }
        }
    }

    return $dt;
}
*parse = \&new;
*parse_date = \&new;
*parse_datetime = \&new;
*date = \&new;
*datetime = \&new;
*new_date = \&new;
*new_datetime = \&new;

1;

__END__
=pod

=head1 NAME

DateTimeX::Easy - Parse a date/time string using the best method available

=head1 VERSION

version 0.089

=head1 SYNOPSIS

    # Make DateTimeX object for "now":
    my $dt = DateTimeX::Easy->new("today");

    # Same thing:
    my $dt = DateTimeX::Easy->new("now");

    # Uses ::F::Natural's coolness (similar in capability to Date::Manip)
    my $dt = DateTimeX::Easy->new("last monday");

    # ... but in 1969:
    my $dt = DateTimeX::Easy->new("last monday", year => 1969);

    # ... at the 100th nanosecond:
    my $dt = DateTimeX::Easy->new("last monday", year => 1969, nanosecond => 100);

    # ... in US/Eastern: (This will NOT do a timezone conversion)
    my $dt = DateTimeX::Easy->new("last monday", year => 1969, nanosecond => 100, timezone => "US/Eastern");

    # This WILL do a proper timezone conversion:
    my $dt = DateTimeX::Easy->new("last monday", year => 1969, nanosecond => 100, timezone => "US/Pacific");
    $dt->set_time_zone("US/Eastern");

    # Custom DateTimeX ability:
    my $dt = DateTimeX::Easy->new("last second of last month");
    $dt = DateTimeX::Easy->new("last second of first month of last year");
    $dt = DateTimeX::Easy->new("last second of first month of 2000");

=head1 DESCRIPTION

DateTimeX::Easy makes DateTime object creation quick and easy. It uses a variety of DateTime::Format packages to do the 
bulk of the parsing, with some custom tweaks to smooth out the rough edges (mainly concerning timezone detection and selection).

=head1 PARSING

Currently, DateTimeX::Easy will attempt to parse input in the following order:

=over

=item DateTime - Is the input a DateTime object?

=item ICal - Was DT::F::ICal able to parse the input?

=item DateParse - Was DT::F::DateParse able to parse the input?

A caveat, I actually use a modified version of DateParse in order to avoid DateParse's default timezone selection.

=item Natural - Was DT::F::Natural able to parse the input?

Since this module barfs pretty loudly on strange input, we use a silent $SIG{__WARN__} to hide errors.

=item Flexible - Was DT::F::Flexible able to parse the input?

This step also looks at the string to see if there is any timezone information at the end.

=item DateManip - Was DT::F::DateManip able to parse the input?

DateManip isn't very nice with preserving the input timezone, but it's here as a last resort.

=back

=head1 "last second of first month of year of 2005"

DateTimeX::Easy also provides additional parsing and transformation for input like:

    "first day of last month"
    "last day of last month"
    "last day of this month"
    "last day of next month"
    "last second of first month of last year"
    "ending day of month of 2007-10-02"
    "last second of first month of year of 2005"
    "last second of last month of year of 2005"
    "beginning day of month of 2007-10-02"
    "last month of year of 2007"

It will look at each sequence of "<first|last> of <period>" and do ->add, ->subtract, and ->truncate operations on the parsed DateTime object

Also, It's best to be as explicit as possible; the following will work:

    "last month of 2007"
    "last second of last month of 2005"
    "beginning day of 2007-10-02"

This won't, though:

    "last day of 2007"

You'll have to do this instead:

    "last day of year of 2007"

The reason is that the date portion is opaque to the parser. It doesn't know whether it has "2007" or "2007-10" or "now" as the last input. To fix this, you can
give a hint to the parser, like "<period> of <date/time>" (as in "year of 2007" above).

WARNING: This feature is still somewhat new, so there may be bugs lurking about. Please forward failing tests/scenarios.

=head1 METHODS

=head2 DateTimeX::Easy->new( ... )

=head2 DateTimeX::Easy->parse( ... )

=head2 DateTimeX::Easy->parse_date( ... )

=head2 DateTimeX::Easy->parse_datetime( ... )

=head2 DateTimeX::Easy->date( ... )

=head2 DateTimeX::Easy->datetime( ... )

=head2 DateTimeX::Easy->new_date( ... )

=head2 DateTimeX::Easy->new_datetime( ... )

Parse the given date/time specification using ::F::Flexible or ::F::Natural and use the result to create a L<DateTime> object. Returns a L<DateTime> object.

You can pass the following in:

    parse       # The string or DateTime object to parse.

    year        # A year to override the result of parsing
    month       # A month to override the result of parsing
    day         # A day to override the result of parsing
    hour        # A hour to override the result of parsing
    minute      # A minute to override the result of parsing
    second      # A second to override the result of parsing

    truncate    # A truncation parameter (e.g. year, day, month, week, etc.)

    time_zone   # - Can be:
    timezone    # * A timezone (e.g. US/Pacific, UTC, etc.)
    tz          # * A DateTime special timezone (e.g. floating, local)
                #
                # - If neither "tz", "timezone", nor "time_zone" is set, then it'll use whatever is parsed.
                # - If no timezone is parsed, then the default is floating.
                # - If the given timezone is different from the parsed timezone,
                #   then a time conversion will take place (unless "soft_time_zone_conversion" is set).
                # - Either "time_zone", "timezone", "tz" will work (in that order), with "time_zone" having highest precedence
                # - See below for examples!

    soft_time_zone_conversion   # Set this flag to 1 if you don't want the time to change when a given timezone is
                                # different from a parsed timezone. For example, "10:00 UTC" soft converted to
                                # PST8PDT would be "10:00 PST8PDT".

    time_zone_if_floating       # The value of this option should be a valid timezone. If this option is set, then a DateTime object
                                # with a floating timezone has it's timezone set to the value.
    default_time_zone           # Same as "time_zone_if_floating"

    ambiguous   # Set this flag to 0 if you want to disallow ambiguous input like:
                # "last day of 2007" or "first minute of April"
                # This will require you to specify them as "last day of year of 2007" and "first minute of month of April"
                # instead. This flag is 1 (false) by default.

    ... and anything else that you want to pass to the DateTime->new constructor

If C<truncate> is specificied, then DateTime->truncate will be run after object creation.

Furthermore, you can simply pass the value for "parse" as the first positional argument of the DateTimeX::Easy call, e.g.:

    # This:
    DateTimeX::Easy->new("today", year => 2008, truncate => "hour");

    # ... is the same as this:
    DateTimeX::Easy->new(parse => "today", year => 2008, truncate => "hour");

Timezone processing can be a little complicated.  Here are some examples:

    DateTimeX::Easy->parse("today"); # Will use a floating timezone

    DateTimeX::Easy->parse("2007-07-01 10:32:10"); # Will ALSO use a floating timezone

    DateTimeX::Easy->parse("2007-07-01 10:32:10 US/Eastern"); # Will use US/Eastern as a timezone

    DateTimeX::Easy->parse("2007-07-01 10:32:10"); # Will use the floating timezone

    DateTimeX::Easy->parse("2007-07-01 10:32:10", time_zone_if_floating => "local"); # Will use the local timezone

    DateTimeX::Easy->parse("2007-07-01 10:32:10 UTC", time_zone => "US/Pacific"); # Will convert from UTC to US/Pacific

    my $dt = DateTime->now->set_time_zone("US/Eastern");
    DateTimeX::Easy->parse($dt); # Will use US/Eastern as the timezone

    DateTimeX::Easy->parse($dt, time_zone => "floating"); # Will use a floating timezone

    DateTimeX::Easy->parse($dt, time_zone => "US/Pacific", soft_time_zone_conversion => 1);
                                                            # Will use US/Pacific as the timezone with NO conversion
                                                            # For example, "22:00 US/Eastern" will become "22:00 PST8PDT" 

    DateTimeX::Easy->parse($dt)->set_time_zone("US/Pacific"); # Will use US/Pacific as the timezone WITH conversion
                                                              # For example, "22:00 US/Eastern" will become "19:00 PST8PDT" 

    DateTimeX::Easy->parse($dt, time_zone => "US/Pacific"); # Will ALSO use US/Pacific as the timezone WITH conversion

=head1 EXPORT

=head2 parse( ... )

=head2 parse_date( ... )

=head2 parse_datetime( ... )

=head2 date( ... )

=head2 datetime( ... )

=head2 new_date( ... )

=head2 new_datetime( ... )

Same syntax as above. See above for more information.

=head1 MOTIVATION

Although I really like using DateTime for date/time handling, I was often frustrated by its inability to parse even the simplest of date/time strings.
There does exist a wide variety of DateTime::Format::* modules, but they all have different interfaces and different capabilities.
Coming from a Date::Manip background, I wanted something that gave me the power of ParseDate while still returning a DateTime object.
Most importantly, I wanted explicit control of the timezone setting at every step of the way. DateTimeX::Easy is the result.

=head1 THANKS

Dave Rolsky and crew for writing L<DateTime>

=head1 SEE ALSO

L<DateTime>

L<DateTime::Format::Natural>

L<DateTime::Format::Flexible>

L<DateTime::Format::ICal>

L<DateTime::Format::DateManip>

L<DateTime::Format::ParseDate>

L<Date::Manip>

=head1 SOURCE

You can contribute or fork this project via GitHub:

L<http://github.com/robertkrimen/datetimex-easy/tree/master>

    git clone git://github.com/robertkrimen/datetimex-easy.git DateTimeX-Easy

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2007 Robert Krimen, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

  Robert Krimen <robertkrimen@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Robert Krimen.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

