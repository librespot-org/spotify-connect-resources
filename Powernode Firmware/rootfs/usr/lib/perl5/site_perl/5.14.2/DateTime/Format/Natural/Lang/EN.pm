package DateTime::Format::Natural::Lang::EN;

use strict;
use warnings;
use base qw(DateTime::Format::Natural::Lang::Base);
# XXX constant.pm true/false: workaround for a segmentation fault
# in Perl_mg_find() on perl 5.8.9 and 5.10.0 when using boolean.pm
# v0.20 (tested as of 12/02/2009).
#use boolean qw(true false);
use constant true  => 1;
use constant false => 0;
use constant skip  => true;

use DateTime::Format::Natural::Helpers qw(%flag);

our $VERSION = '1.57';

our (%init,
     %timespan,
     %units,
     %suffixes,
     %regexes,
     %RE,
     %data_weekdays,
     %data_weekdays_abbrev,
     @data_weekdays_all,
     %data_months,
     %data_months_abbrev,
     @data_months_all,
     %data_conversion,
     %data_helpers,
     %data_duration,
     %data_aliases,
     %data_rewrite,
     %extended_checks,
     %grammar);

%init     = (tokens  => sub {});
%timespan = (literal => 'to');
%units    = (ordered => [ qw(second minute hour day week month year) ]);
%suffixes = (ordinal => join '|', qw(st nd rd th d));
%regexes  = (format  => qr!^((?:\d+?(?:-(?:[a-zA-Z]+?|\d+?)-|[./]\d+?[./])\d+?) | (?:\d+?/\d+?)) (?:(?=\s)|$)!x);

%RE = (number    => qr/^(\d+)$/,
       year      => qr/^(\d{4})$/,
       time      => qr/^((?:\d{1,2})(?:\:\d{2}){0,2})$/,
       time_am   => qr/^((?:\d{1,2})(?:\:\d{2}){0,2})am$/i,
       time_pm   => qr/^((?:\d{1,2})(?:\:\d{2}){0,2})pm$/i,
       time_min  => qr/^(\d{1,2}(?:\:\d{2}){1,2})$/,
       day       => qr/^(\d+)($suffixes{ordinal})?$/i,
       monthday  => qr/^(\d{1,2})($suffixes{ordinal})?$/i);
{
    my $sort = sub
    {
        my ($data) = @_;
        return sort { $data->{$a} <=> $data->{$b} } keys %$data;
    };
    my $sort_abbrev = sub
    {
        my ($data_abbrev, $data) = @_;
        return sort {
            $data->{$data_abbrev->{$a}} <=> $data->{$data_abbrev->{$b}}
        } keys %$data_abbrev;
    };

    my $i = 1;

    %data_weekdays = map {
        $_ => $i++
    } qw(Monday Tuesday Wednesday Thursday Friday Saturday Sunday);
    %data_weekdays_abbrev = map {
        substr($_, 0, 3) => $_
    } keys %data_weekdays;

    @data_weekdays_all = ($sort->(\%data_weekdays), $sort_abbrev->(\%data_weekdays_abbrev, \%data_weekdays));

    my $days_re = join '|', @data_weekdays_all;
    $RE{weekday} = qr/^($days_re)$/i;

    $days_re = join '|', map "${_}s?", @data_weekdays_all;
    $RE{weekdays} = qr/^($days_re)$/i;

    $i = 1;

    %data_months = map {
        $_ => $i++
    } qw(January February March April May June July August September
         October November December);
    %data_months_abbrev = map {
        substr($_, 0, 3) => $_
    } keys %data_months;

    @data_months_all = ($sort->(\%data_months), $sort_abbrev->(\%data_months_abbrev, \%data_months));

    my $months_re = join '|', @data_months_all;
    $RE{month} = qr/^($months_re)$/i;

    %data_conversion = (
        last_this_next    => { do { $i = -1; map { $_ => $i++ } qw(last this next)           } },
        yes_today_tom     => { do { $i = -1; map { $_ => $i++ } qw(yesterday today tomorrow) } },
        noon_midnight     => { noon => 12, midnight => 0                                       },
        morn_aftern_even  => { do { $i = 0; map { $_ => $i++ } qw(morning afternoon evening) } },
        before_after_from => { before => -1, after => 1, from => 1                             },
    );

    %data_helpers = (
        suffix      => qr/s$/i,
        normalize   => sub { ${$_[0]} = ucfirst lc ${$_[0]} },
        abbreviated => sub { length ${$_[0]} == 3 },
    );

    %data_duration = (
        for => {
            regex   => qr/^for \s+ .+$/ix,
            present => 'now',
        },
        first_to_last => {
            regexes => {
                first   => qr/^first$/i,
                last    => qr/^last \s+ .+$/ix,
                extract => qr/^\S+? \s+ (.+)$/x,
            },
        },
        from_count_to_count => {
            regexes => {
                time_meridiem => qr/\d{1,2}(?:\:\d{2}){0,2}(?:\s*?(?:am|pm))/i,
                time          => qr/\d{1,2}(?:\:\d{2}){1,2}/,
                day_ordinal   => qr/\d{1,3}(?:$suffixes{ordinal})/i,
                day           => qr/\d{1,3}/,
            },
            order => [qw(
                time_meridiem
                time
                day_ordinal
                day
            )],
            categories => {
                time_meridiem => 'time',
                time          => 'time',
                day_ordinal   => 'day',
                day           => 'day',
            },
        },
    );

    %data_aliases = (
        words => {
            tues  => 'tue',
            thur  => 'thu',
            thurs => 'thu',
        },
        tokens => {
            mins => 'minutes',
            '@'  => 'at',
        },
        short => {
            min => 'minute',
            d   => 'day',
        },
    );

    %data_rewrite = (
        at => {
            match   => qr/\S+? \s+? at \s+? \S+$/ix,
            subst   => qr/\s+? at \b/ix,
            daytime => qr/^(?:noon|midnight)$/i,
        },
    );
}

%extended_checks = (
    meridiem => sub
    {
        my ($first_stack, $rest_stack, $pos, $error) = @_;

        my ($hour) = split /:/, $first_stack->{$pos->[0]};

        if ($hour == 0) {
            $$error = 'hour zero must be literal 12';
            return false;
        }
        elsif ($hour > 12) {
            $$error = 'hour exceeds 12-hour clock';
            return false;
        }
        return true;
    },
    ordinal => sub
    {
        my ($first_stack, $rest_stack, $pos, $error) = @_;

        my $suffix = do {
            local $_ = $rest_stack->{$pos->[0]}->[0];
            defined $_ ? lc $_ : undef;
        };
        return skip unless defined $suffix;

        my $numeral = $first_stack->{$pos->[0]};

        my %ordinals = (
            1 => { regex => qr/^st$/,  suffix => 'st' },
            2 => { regex => qr/^n?d$/, suffix => 'nd' },
            3 => { regex => qr/^r?d$/, suffix => 'rd' },
        );

        my $fail_message = sub { "letter suffix should be '$_[0]'" };

        local $1;
        if ($numeral == 0) {
            unless ($suffix eq 'th') {
                $$error = $fail_message->('th');
                return false;
            }
            return true;
        }
        elsif ($numeral =~ /([1-3])$/ && $numeral !~ /1\d$/) {
            unless ($suffix =~ $ordinals{$1}->{regex}) {
                $$error = $fail_message->($ordinals{$1}->{suffix});
                return false;
            }
            return true;
        }
        elsif ($numeral > 3) {
            unless ($suffix eq 'th') {
                $$error = $fail_message->('th');
                return false;
            }
            return true;
        }
        return skip; # never reached
    },
    suffix => sub
    {
        my ($first_stack, $rest_stack, $pos, $error) = @_;

        my @checks = (
            { cond  => sub { $first_stack->{$pos->[0]} == 1 && $first_stack->{$pos->[1]} =~ $data_helpers{suffix} },
              error => "suffix 's' without plural",
            },
            { cond  => sub { $first_stack->{$pos->[0]} >  1 && $first_stack->{$pos->[1]} !~ $data_helpers{suffix} },
              error => "plural without suffix 's'",
            },
        );
        foreach my $check (@checks) {
            if ($check->{cond}->()) {
                $$error = $check->{error};
                return false;
            }
        }
        return true;
    },
);

# <keyword> => [
#    [ <PERL TYPE DECLARATION>, ... ], ---------------------> declares how the tokens will be evaluated
#    [
#      { <token index> => <token value>, ... }, ------------> declares the index <-> value map
#      [ [ <index(es) of token(s) to be passed> ], ... ], --> declares which tokens will be passed to the extended check(s)
#      [ <subroutine(s) for extended check(s)>, ... ], -----> declares the extended check(s)
#      [ [ <index(es) of token(s) to be passed> ], ... ], --> declares which tokens will be passed to the worker method(s)
#      [ { <additional options to be passed> }, ... ], -----> declares additional options
#      [ <name of method to dispatch to>, ... ], -----------> declares the worker method(s)
#      { <shared option>, ... }, ---------------------------> declares shared options (post-processed)
#    ],

#
# NOTE: the grammar here does not cover all valid input string
# variations; see Rewrite.pm for how date strings are rewritten
# before parsing.
#

%grammar = (
    now => [
       [ 'SCALAR' ],
       [
         { 0 => 'now' },
         [],
         [],
         [ [] ],
         [ {} ],
         [ '_no_op' ],
         {},
       ],
    ],
    day => [
       [ 'REGEXP' ],
       [
         { 0 => qr/^(today)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
    ],
    daytime => [
       [ 'REGEXP' ],
       [
         { 0 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         { truncate_to => [q(hour)] },
       ]
    ],
    daytime_noon_midnight => [
       [ 'REGEXP' ],
       [
         { 0 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ {} ],
         [ '_daytime' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ]
         ],
         [ {} ],
         [ '_daytime' ],
         { truncate_to => [q(hour)] },
       ],
    ],
    daytime_noon_midnight_at => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{noon_midnight} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
    ],
    daytime_variant_weekday => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(noon)$/i, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(midnight)$/i, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(noon)$/i, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(midnight)$/i, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(noon)$/i, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(midnight)$/i, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour)] },
       ],
    ],
    this_daytime => [
       [ 'SCALAR', 'REGEXP' ],
       [
         { 0 => 'this', 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => 'this', 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ {} ],
         [ '_daytime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => 'this', 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         { truncate_to => [q(hour)] },
       ],
    ],
    daytime_day => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         { truncate_to => [undef, q(hour)] },
       ],
    ],
    weekday_daytime => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ {}, {} ],
         [ '_weekday', '_daytime_variant' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour)],
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_daytime_variant' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour)],
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ {}, {} ],
         [ '_weekday', '_daytime_variant' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour)],
         },
       ],
    ],
    at_daytime => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{time}, 1 => qr/^(yesterday)$/i },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_time', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(today)$/i },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_time', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(tomorrow)$/i },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_time', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(yesterday)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(today)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(tomorrow)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(yesterday)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(today)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(tomorrow)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    at_variant_weekday => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{time}, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    variant_weekday_at => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{weekday}, 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{weekday}, 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{weekday}, 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{weekday}, 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{weekday}, 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{weekday}, 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    month => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_date' ],
         {
           prefer_future => true,
           truncate_to   => [q(month)],
         },
       ],
    ],
    month_day => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_day' ],
         {
           prefer_future => true,
           truncate_to   => [q(day)],
         },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_day' ],
         {
           prefer_future => true,
           truncate_to   => [q(day)],
         },
       ]
    ],
    month_day_at => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{time_min} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_month_day', '_time' ],
         { truncate_to => [undef, q(minute)] },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{time_am} },
         [ [ 1 ], [ 2 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_month_day', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{time_pm} },
         [ [ 1 ], [ 2 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_month_day', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    month_day_year_at => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year}, 3 => $RE{time_min} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
           [ 3 ],
         ],
         [ {}, { unit => 'year' }, {} ],
         [ '_month_day', '_unit_date', '_time' ],
         { truncate_to => [undef, undef, q(minute)] },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year}, 3 => $RE{time_am} },
         [ [ 1 ], [ 3 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
           [
             { 3 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, { unit => 'year' }, {} ],
         [ '_month_day', '_unit_date', '_at' ],
         { truncate_to => [undef, undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year}, 3 => $RE{time_pm} },
         [ [ 1 ], [ 3 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
           [
             { 3 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, { unit => 'year' }, {} ],
         [ '_month_day', '_unit_date', '_at' ],
         { truncate_to => [undef, undef, q(hour_minute)] },
       ],
    ],
    day_month_at => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{time_min} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_month_day', '_time' ],
         { truncate_to => [undef, q(minute)] },
       ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{time_am} },
         [ [ 0 ], [ 2 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_month_day', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{time_pm} },
         [ [ 0 ], [ 2 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_month_day', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    day_month_year_at => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{year}, 3 => $RE{time_min} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
           [ 3 ],
         ],
         [ {}, { unit => 'year' }, {} ],
         [ '_month_day', '_unit_date', '_time' ],
         { truncate_to => [undef, undef, q(minute)] },
       ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{year}, 3 => $RE{time_am} },
         [ [ 0 ], [ 3 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
           [
             { 3 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, { unit => 'year' }, {} ],
         [ '_month_day', '_unit_date', '_at' ],
         { truncate_to => [undef, undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{year}, 3 => $RE{time_pm} },
         [ [ 0 ], [ 3 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
           [
             { 3 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, { unit => 'year' }, {} ],
         [ '_month_day', '_unit_date', '_at' ],
         { truncate_to => [undef, undef, q(hour_minute)] },
       ],
    ],
    at_month_day => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{time_min}, 1 => $RE{month}, 2 => $RE{monthday} },
         [ [ 2 ] ],
         [ $extended_checks{ordinal} ],
         [
           [ 0 ],
           [
               2,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_month_day' ],
         { truncate_to => [undef, q(minute)] },
       ],
       [
         { 0 => $RE{time_am}, 1 => $RE{month}, 2 => $RE{monthday} },
         [ [ 0 ], [ 2 ] ],
         [ $extended_checks{meridiem}, $extended_checks{ordinal} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
               2,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_month_day' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{time_pm}, 1 => $RE{month}, 2 => $RE{monthday} },
         [ [ 0 ], [ 2 ] ],
         [ $extended_checks{meridiem}, $extended_checks{ordinal} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
               2,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_month_day' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    day_month_year_ago => [
      [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{number}, 3 => qr/^(years?)$/i, 4 => 'ago' },
        [ [ 0 ], [ 2, 3 ] ],
        [ $extended_checks{ordinal}, $extended_checks{suffix} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [ 2 ],
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_ago_variant' ],
        { truncate_to => [undef, q(day)] },
      ],
    ],
    day_month_variant_year => [
      [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => qr/^(next)$/i, 3 => 'year' },
        [ [ 0 ] ],
        [ $extended_checks{ordinal} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [
            { 2 => [ $flag{last_this_next} ] },
          ],
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_unit_variant' ],
        { truncate_to => [undef, q(day)] },
      ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => qr/^(this)$/i, 3 => 'year' },
        [ [ 0 ] ],
        [ $extended_checks{ordinal} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [
            { 2 => [ $flag{last_this_next} ] },
          ],
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_unit_variant' ],
        { truncate_to => [undef, q(day)] },
      ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => qr/^(last)$/i, 3 => 'year' },
        [ [ 0 ] ],
        [ $extended_checks{ordinal} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [
            { 2 => [ $flag{last_this_next} ] },
          ]
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_unit_variant' ],
        { truncate_to => [undef, q(day)] },
      ],
    ],
    month_day_year => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, { unit => 'year' } ],
         [ '_month_day', '_unit_date' ],
         { truncate_to => [undef, q(day)] },
       ],
    ],
    year_month_day => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{year}, 1 => $RE{month}, 2 => $RE{monthday} },
         [ [ 2 ] ],
         [ $extended_checks{ordinal} ],
         [
           [ 0 ],
           [
               2,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ { unit => 'year' }, {} ],
         [ '_unit_date', '_month_day' ],
         { truncate_to => [undef, q(day)] },
       ],
    ],
    week_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(next)$/i, 1 => 'week' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'week' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'week' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ]
         ],
         [ { unit => 'week' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ]
    ],
    weekday => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ]
         ],
         [ {} ],
         [ '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [q(day)],
         },
       ],
    ],
    weekday_variant => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
    ],
    year_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(last)$/i, 1 => 'year' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(year)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'year' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(year)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'year' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(year)] }
       ],
    ],
    month_variant => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_variant' ],
         { truncate_to => [q(month)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ]
         ],
         [ {} ],
         [ '_month_variant' ],
         { truncate_to => [q(month)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_variant' ],
         { truncate_to => [q(month)] },
       ],
    ],
    time_literal_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(last)$/i, 1 => 'second' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_unit_variant' ],
         {},
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'second' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_unit_variant' ],
         {},
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'second' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_unit_variant' ],
         {},
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'minute' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(minute)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'minute' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(minute)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'minute' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(minute)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'hour' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'hour' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'hour' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(hour)] },
       ],
    ],
    date_literal_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(last)$/i, 1 => 'day' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'day' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'day' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'month' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(month)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'month' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(month)] },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'month' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_variant' ],
         { truncate_to => [q(month)] },
       ],
    ],
    at => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{time_am} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
         ],
         [ {} ],
         [ '_at' ],
         {
           prefer_future => true,
           truncate_to   => [q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{time_pm} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
         ],
         [ {} ],
         [ '_at' ],
         {
           prefer_future => true,
           truncate_to   => [q(hour_minute)],
         },
       ],
    ],
    weekday_time => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, {} ],
         [ '_weekday', '_time' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{time}, 1 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{time_am}, 1 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{time_pm}, 1 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
    ],
    time => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{time} },
         [],
         [],
         [ [ 0 ] ],
         [ {} ],
         [ '_time' ],
         {
           prefer_future => true,
           truncate_to   => [q(hour_minute)],
         },
       ],
    ],
    month_year => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{year} },
         [],
         [],
         [
           [
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'month' }, { unit => 'year' } ],
         [ '_unit_date', '_unit_date' ],
         { truncate_to => [undef, q(month)] },
       ],
    ],
    year => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{year} },
         [],
         [],
         [ [ 0 ] ],
         [ { unit => 'year' } ],
         [ '_unit_date' ],
         { truncate_to => [q(year)] },
       ],
    ],
    count_weekday => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday' ],
         { truncate_to => [q(day)] },
       ],
    ],
    count_yearday => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'day' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             0,
             { VALUE => 0 }
           ],
         ],
         [ {} ],
         [ '_count_yearday_variant_year' ],
         { truncate_to => [q(day)] },
       ],
    ],
    count_yearday_variant_year => [
        [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
        [
          { 0 => $RE{day}, 1 => 'day', 2 => qr/^(next)$/i, 3 => 'year' },
          [ [ 0 ] ],
          [ $extended_checks{ordinal} ],
          [
            [
                0,
              { 2 => [ $flag{last_this_next} ] },
            ],
          ],
          [ {} ],
          [ '_count_yearday_variant_year' ],
          { truncate_to => [q(day)] },
        ],
        [
          { 0 => $RE{day}, 1 => 'day', 2 => qr/^(this)$/i, 3 => 'year' },
          [ [ 0 ] ],
          [ $extended_checks{ordinal} ],
          [
            [
                0,
              { 2 => [ $flag{last_this_next} ] },
            ],
          ],
          [ {} ],
          [ '_count_yearday_variant_year' ],
          { truncate_to => [q(day)] },
        ],
        [
          { 0 => $RE{day}, 1 => 'day', 2 => qr/^(last)$/i, 3 => 'year' },
          [ [ 0 ] ],
          [ $extended_checks{ordinal} ],
          [
            [
                0,
              { 2 => [ $flag{last_this_next} ] },
            ],
          ],
          [ {} ],
          [ '_count_yearday_variant_year' ],
          { truncate_to => [q(day)] },
        ],
    ],
    daytime_in_the_variant => [
       [ 'REGEXP', 'SCALAR', 'SCALAR', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => 'in', 2 => 'the', 3 => 'morning' },
         [],
         [],
         [ [ 0 ] ],
         [ {} ],
         [ '_daytime' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => 'in', 2 => 'the', 3 => 'afternoon' },
         [],
         [],
         [ [ 0 ] ],
         [ { hours => 12 } ],
         [ '_daytime' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => 'in', 2 => 'the', 3 => 'evening' },
         [],
         [],
         [ [ 0 ] ],
         [ { hours => 12 } ],
         [ '_daytime' ],
         { truncate_to => [q(hour)] },
       ],
    ],
    ago => [
       [ 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(seconds?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'second' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(minutes?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'minute' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'hour' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(days?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'day' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(weeks?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'week' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(months?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'month' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(years?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'year' } ],
         [ '_ago_variant' ],
         {},
       ],
    ],
    ago_tomorrow => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(seconds?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'second' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(minutes?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'minute' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(hours?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'hour' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(days?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'day' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(weeks?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'week' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'month' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(years?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'year' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
    ],
    ago_today => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(seconds?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'second' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(minutes?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'minute' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(hours?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'hour' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(days?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'day' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(weeks?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'week' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'month' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{number}, 2 => qr/^(years?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'year' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
    ],
    ago_yesterday => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(seconds?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'second' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(minutes?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'minute' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(hours?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'hour' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(days?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'day' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(weeks?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'week' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'month' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(years?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'year' } ],
         [ '_unit_variant', '_ago_variant' ],
         { truncate_to => [undef, q(day)] },
       ],
    ],
    weekday_ago_at_time => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago', 4 => $RE{time_min} },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 4 ],
         ],
         [ { unit => 'month' }, {}, {} ],
         [ '_ago_variant', '_weekday', '_time' ],
         { truncate_to => [undef, undef, q(minute)] },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago', 4 => $RE{time_am} },
         [ [ 1, 2 ], [ 4 ] ],
         [ $extended_checks{suffix}, $extended_checks{meridiem} ],
         [
           [ 1 ],
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 4 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'month' }, {}, {} ],
         [ '_ago_variant', '_weekday', '_at' ],
         { truncate_to => [undef, undef, q(hour_minute)] },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago', 4 => $RE{time_pm} },
         [ [ 1, 2 ], [ 4 ] ],
         [ $extended_checks{suffix}, $extended_checks{meridiem} ],
         [
           [ 1 ],
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 4 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'month' }, {}, {} ],
         [ '_ago_variant', '_weekday', '_at' ],
         { truncate_to => [undef, undef, q(hour_minute)] },
       ],
    ],
    now_variant_before => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(seconds?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(minutes?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(days?)$/i,  2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(weeks?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(months?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ]
         ],
         [ { unit => 'month' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(years?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_now_variant' ],
         {},
       ],
    ],
    now_variant_from => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(seconds?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(minutes?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(days?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(weeks?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(months?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(years?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_now_variant' ],
         {},
       ],
    ],
    day_daytime => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'SCALAR', 'SCALAR' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => 'in', 3 => 'the', 4 => 'morning' },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, {} ],
         [ '_weekday', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => 'in', 3 => 'the', 4 => 'afternoon' },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, { hours => 12 } ],
         [ '_weekday', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => 'in', 3 => 'the', 4 => 'evening' },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, { hours => 12 } ],
         [ '_weekday', '_daytime' ],
         { truncate_to => [undef, q(hour)] },
       ],
    ],
    variant_weekday_at_time => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{weekday}, 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_time' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{weekday}, 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_time' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{weekday}, 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_time' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    count_day_variant_week => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(next)$/i, 3 => 'week' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(this)$/i, 3 => 'week' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(last)$/i, 3 => 'week' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
    ],
    count_day_variant_month => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(next)$/i, 3 => 'month' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_month' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(this)$/i, 3 => 'month' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_month' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(last)$/i, 3 => 'month' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_month' ],
         { truncate_to => [q(day)] },
       ],
    ],
    weekday_variant_week => [
       [ 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(next)$/i, 2 => 'week' },
         [],
         [],
         [
           [
             { 1 => [ $flag{last_this_next} ] },
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(this)$/i, 2 => 'week' },
         [],
         [],
         [
           [
             { 1 => [ $flag{last_this_next} ] },
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(last)$/i, 2 => 'week' },
         [],
         [],
         [
           [
             { 1 => [ $flag{last_this_next} ] },
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ]
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
    ],
    variant_week_weekday => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => qr/^(next)$/i, 1 => 'week', 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'week', 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'week', 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => [q(day)] },
       ],
    ],
    count_month_variant_year => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'month', 2 => qr/^(next)$/i, 3 => 'year' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_month_variant_year' ],
         { truncate_to => [q(month)] },
       ],
       [
         { 0 => $RE{day}, 1 => 'month', 2 => qr/^(this)$/i, 3 => 'year' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_month_variant_year' ],
         { truncate_to => [q(month)] },
       ],
       [
         { 0 => $RE{day}, 1 => 'month', 2 => qr/^(last)$/i, 3 => 'year' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_month_variant_year' ],
         { truncate_to => [q(month)] },
       ],
    ],
    in_count_unit => [
       [ 'SCALAR', 'REGEXP', 'REGEXP' ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(seconds?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'second' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(minutes?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'minute' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(hours?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'hour' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(days?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'day' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(weeks?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'week' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(months?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'month' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(years?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'year' } ],
         [ '_in_count_variant' ],
         {},
       ],
    ],
    count_weekday_variant_month => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => qr/^(next)$/i, 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => qr/^(this)$/i, 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => qr/^(last)$/i, 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => [q(day)] },
       ],
    ],
    daytime_hours_variant => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => qr/^(yesterday)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => qr/^(tomorrow)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => qr/^(yesterday)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => qr/^(tomorrow)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => [q(hour)] },
       ],
    ],
    hourtime_before_variant => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => 'noon' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { hours => 12 } ],
         [ '_hourtime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => 'midnight' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ {} ],
         [ '_hourtime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => 'noon' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { hours => 12 } ],
         [ '_hourtime_variant' ],
         { truncate_to => [q(hour)] },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => 'midnight' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ {} ],
         [ '_hourtime_variant' ],
         { truncate_to => [q(hour)] },
       ],
    ],
    day_at => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => [undef, q(hour_minute)] },
       ],
    ],
    time_on_weekday => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{time}, 1 => 'on', 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{time_am}, 1 => 'on', 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
       [
         { 0 => $RE{time_pm}, 1 => 'on', 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => [undef, q(hour_minute)],
         },
       ],
    ],
    day_month_year => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{year} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
               2,
           ],
         ],
         [ {} ],
         [ '_day_month_year' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
               2,
           ],
         ],
         [ {} ],
         [ '_day_month_year' ],
         { truncate_to => [q(day)] },
       ],
    ],
    count_weekday_in_month => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => 'in', 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { VALUE => 0 },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => [q(day)] },
       ],
    ],
    count_weekday_from_now => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => $RE{weekdays}, 2 => 'from', 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_from_now' ],
         { truncate_to => [q(day)] },
       ],
    ],
    final_weekday_in_month => [
       [ 'SCALAR', 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => 'final', 1 => $RE{weekday}, 2 => 'in', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_final_weekday_in_month' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => 'last', 1 => $RE{weekday}, 2 => 'in', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_final_weekday_in_month' ],
         { truncate_to => [q(day)] },
       ],
    ],
    for_count_unit => [
       [ 'SCALAR', 'REGEXP', 'REGEXP' ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(seconds?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'second' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(minutes?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'minute' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(hours?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'hour' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(days?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'day' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(weeks?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'week' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(months?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'month' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(years?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'year' } ],
         [ '_in_count_variant' ],
         {},
       ],
    ],
    first_last_day_unit => [
       [ 'SCALAR', 'SCALAR', 'SCALAR', 'REGEXP' ],
       [
         { 0 => 'first', 1 => 'day', 2 => 'of', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
             { VALUE => 1 },
           ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => 'first', 1 => 'day', 2 => 'of', 3 => $RE{year} },
         [],
         [],
         [
           [
               3,
             { VALUE => 1 },
             { VALUE => 1 },
           ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => 'last', 1 => 'day', 2 => 'of', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
             { VALUE => undef },
           ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => [q(day)] },
       ],
       [
         { 0 => 'last', 1 => 'day', 2 => 'of', 3 => $RE{year} },
         [],
         [],
         [
           [
                3,
              { VALUE => 12 },
              { VALUE => undef },
            ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => [q(day)] },
       ],
    ],
);

1;
__END__

=head1 NAME

DateTime::Format::Natural::Lang::EN - English language metadata

=head1 DESCRIPTION

C<DateTime::Format::Natural::Lang::EN> provides the english specific grammar
and variables. This class is loaded if the user either specifies the english
language or implicitly.

=head1 EXAMPLES

Below are some examples of human readable date/time input in english (be aware
that the parser does not distinguish between lower/upper case; furthermore,
many expressions allow for additional leading/trailing time and all times are
also parsable with precision in seconds):

=head2 Simple

 now
 yesterday
 today
 tomorrow
 morning
 afternoon
 evening
 noon
 midnight
 yesterday at noon
 yesterday at midnight
 today at noon
 today at midnight
 tomorrow at noon
 tomorrow at midnight
 this morning
 this afternoon
 this evening
 yesterday morning
 yesterday afternoon
 yesterday evening
 today morning
 today afternoon
 today evening
 tomorrow morning
 tomorrow afternoon
 tomorrow evening
 thursday morning
 thursday afternoon
 thursday evening
 6:00 yesterday
 6:00 today
 6:00 tomorrow
 5am yesterday
 5am today
 5am tomorrow
 4pm yesterday
 4pm today
 4pm tomorrow
 last second
 this second
 next second
 last minute
 this minute
 next minute
 last hour
 this hour
 next hour
 last day
 this day
 next day
 last week
 this week
 next week
 last month
 this month
 next month
 last year
 this year
 next year
 last friday
 this friday
 next friday
 tuesday last week
 tuesday this week
 tuesday next week
 last week wednesday
 this week wednesday
 next week wednesday
 10 seconds ago
 10 minutes ago
 10 hours ago
 10 days ago
 10 weeks ago
 10 months ago
 10 years ago
 in 5 seconds
 in 5 minutes
 in 5 hours
 in 5 days
 in 5 weeks
 in 5 months
 in 5 years
 saturday
 sunday 11:00
 yesterday at 4:00
 today at 4:00
 tomorrow at 4:00
 yesterday at 6:45am
 today at 6:45am
 tomorrow at 6:45am
 yesterday at 6:45pm
 today at 6:45pm
 tomorrow at 6:45pm
 yesterday at 2:32 AM
 today at 2:32 AM
 tomorrow at 2:32 AM
 yesterday at 2:32 PM
 today at 2:32 PM
 tomorrow at 2:32 PM
 yesterday 02:32
 today 02:32
 tomorrow 02:32
 yesterday 2:32am
 today 2:32am
 tomorrow 2:32am
 yesterday 2:32pm
 today 2:32pm
 tomorrow 2:32pm
 wednesday at 14:30
 wednesday at 02:30am
 wednesday at 02:30pm
 wednesday 14:30
 wednesday 02:30am
 wednesday 02:30pm
 friday 03:00 am
 friday 03:00 pm
 sunday at 05:00 am
 sunday at 05:00 pm
 2nd monday
 100th day
 4th february
 november 3rd
 last june
 next october
 6 am
 5am
 5:30am
 8 pm
 4pm
 4:20pm
 06:56:06 am
 06:56:06 pm
 mon 2:35
 1:00 sun
 1am sun
 1pm sun
 1:00 on sun
 1am on sun
 1pm on sun
 12:14 PM
 12:14 AM

=head2 Complex

 yesterday 7 seconds ago
 yesterday 7 minutes ago
 yesterday 7 hours ago
 yesterday 7 days ago
 yesterday 7 weeks ago
 yesterday 7 months ago
 yesterday 7 years ago
 today 5 seconds ago
 today 5 minutes ago
 today 5 hours ago
 today 5 days ago
 today 5 weeks ago
 today 5 months ago
 today 5 years ago
 tomorrow 3 seconds ago
 tomorrow 3 minutes ago
 tomorrow 3 hours ago
 tomorrow 3 days ago
 tomorrow 3 weeks ago
 tomorrow 3 months ago
 tomorrow 3 years ago
 2 seconds before now
 2 minutes before now
 2 hours before now
 2 days before now
 2 weeks before now
 2 months before now
 2 years before now
 4 seconds from now
 4 minutes from now
 4 hours from now
 4 days from now
 4 weeks from now
 4 months from now
 4 years from now
 6 in the morning
 4 in the afternoon
 9 in the evening
 monday 6 in the morning
 monday 4 in the afternoon
 monday 9 in the evening
 last sunday at 21:45
 monday last week
 6th day last week
 6th day this week
 6th day next week
 12th day last month
 12th day this month
 12th day next month
 1st day last year
 1st day this year
 1st day next year
 1st tuesday last november
 1st tuesday this november
 1st tuesday next november
 11 january next year
 11 january this year
 11 january last year
 6 hours before yesterday
 6 hours before tomorrow
 3 hours after yesterday
 3 hours after tomorrow
 10 hours before noon
 10 hours before midnight
 5 hours after noon
 5 hours after midnight
 noon last friday
 midnight last friday
 noon this friday
 midnight this friday
 noon next friday
 midnight next friday
 last friday at 20:00
 this friday at 20:00
 next friday at 20:00
 1:00 last friday
 1:00 this friday
 1:00 next friday
 1am last friday
 1am this friday
 1am next friday
 1pm last friday
 1pm this friday
 1pm next friday
 5 am last monday
 5 am this monday
 5 am next monday
 5 pm last monday
 5 pm this monday
 5 pm next monday
 last wednesday 7am
 this wednesday 7am
 next wednesday 7am
 last wednesday 7pm
 this wednesday 7pm
 next wednesday 7pm
 last tuesday 11 am
 this tuesday 11 am
 next tuesday 11 am
 last tuesday 11 pm
 this tuesday 11 pm
 next tuesday 11 pm
 yesterday at 13:00
 today at 13:00
 tomorrow at 13
 2nd friday in august
 3rd wednesday in november
 tomorrow 1 year ago
 saturday 3 months ago at 17:00
 saturday 3 months ago at 5:00am
 saturday 3 months ago at 5:00pm
 11 january 2 years ago
 4th day last week
 8th month last year
 8th month this year
 8th month next year
 6 mondays from now
 fri 3 months ago at 5am
 wednesday 1 month ago at 8pm
 final thursday in april
 last thursday in april

=head2 Timespans

 monday to friday
 1 April to 31 August
 1999-12-31 to tomorrow
 now to 2010-01-01
 2009-03-10 9:00 to 11:00
 26 oct 10:00 am to 11:00 am
 jan 1 to 2
 16:00 nov 6 to 17:00
 may 2nd to 5th
 100th day to 200th
 6am dec 5 to 7am
 1/3 to 2/3
 2/3 to in 1 week
 3/3 21:00 to in 5 days
 first day of 2009 to last day of 2009
 first day of may to last day of may
 first to last day of 2008
 first to last day of september
 for 4 seconds
 for 4 minutes
 for 4 hours
 for 4 days
 for 4 weeks
 for 4 months
 for 4 years

=head2 Specific

 march
 january 11
 11 january
 18 oct 17:00
 18 oct 5am
 18 oct 5pm
 18 oct 5 am
 18 oct 5 pm
 dec 25
 feb 28 3:00
 feb 28 3am
 feb 28 3pm
 feb 28 3 am
 feb 28 3 pm
 19:00 jul 1
 7am jul 1
 7pm jul 1
 7 am jul 1
 7 pm jul 1
 jan 24, 2011 12:00
 jan 24, 2011 12am
 jan 24, 2011 12pm
 may 27th
 2005
 march 1st 2009
 October 2006
 february 14, 2004
 jan 3 2010
 3 jan 2000
 2010 october 28
 2011-jan-04
 27/5/1979
 1/3
 1/3 16:00
 4:00
 17:00
 3:20:00
 -5min
 +2d
 20111018000000

=head2 Aliases

 5 mins ago
 yesterday @ noon
 tues this week
 final thurs in sep
 tues
 thurs
 thur

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
