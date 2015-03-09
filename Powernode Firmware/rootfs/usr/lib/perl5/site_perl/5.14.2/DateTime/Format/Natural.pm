package DateTime::Format::Natural;

use strict;
use warnings;
use base qw(
    DateTime::Format::Natural::Calc
    DateTime::Format::Natural::Duration
    DateTime::Format::Natural::Expand
    DateTime::Format::Natural::Extract
    DateTime::Format::Natural::Formatted
    DateTime::Format::Natural::Helpers
    DateTime::Format::Natural::Rewrite
);
use boolean qw(true false);

use Carp qw(croak);
use DateTime ();
use DateTime::TimeZone ();
use List::MoreUtils qw(all any none);
use Params::Validate ':all';
use Scalar::Util qw(blessed);
use Storable qw(dclone);

our $VERSION = '1.00';

validation_options(
    on_fail => sub
{
    my ($error) = @_;
    chomp $error;
    croak $error;
},
    stack_skip => 2,
);

sub new
{
    my $class = shift;

    my $self = bless {}, ref($class) || $class;

    $self->_init_check(@_);
    $self->_init(@_);

    return $self;
}

sub _init
{
    my $self = shift;
    my %opts = @_;

    my %presets = (
        lang          => 'en',
        format        => 'd/m/y',
        prefer_future =>  false,
        time_zone     => 'floating',
    );
    foreach my $opt (keys %presets) {
        $self->{ucfirst $opt} = $presets{$opt};
    }
    foreach my $opt (keys %opts) {
        if (defined $opts{$opt}) {
            $self->{ucfirst $opt} = $opts{$opt};
        }
    }
    $self->{Daytime} = $opts{daytime} || {};

    my $mod = join '::', (__PACKAGE__, 'Lang', uc $self->{Lang});
    eval "require $mod"; die $@ if $@;

    $self->{data} = $mod->__new();
    $self->{grammar_class} = $mod;
}

sub _init_check
{
    my $self = shift;

    validate(@_, {
        lang => {
            type => SCALAR,
            optional => true,
            regex => qr!^(?:en)$!i,
        },
        format => {
            type => SCALAR,
            optional => true,
            regex => qr!^(?:[dmy]{1,4}[-./]){2}[dmy]{1,4}$!i,
        },
        prefer_future => {
            # SCALARREF due to boolean.pm's implementation
            type => BOOLEAN | SCALARREF,
            optional => true,
        },
        time_zone => {
            type => SCALAR | OBJECT,
            optional => true,
            callbacks => {
                'valid timezone' => sub
                {
                    my $val = shift;
                    if (blessed($val)) {
                        return $val->isa('DateTime::TimeZone');
                    }
                    else {
                        eval { DateTime::TimeZone->new(name => $val) };
                        return !$@;
                    }
                }
            },
        },
        daytime => {
            type => HASHREF,
            optional => true,
        },
        datetime => {
            type => OBJECT,
            optional => true,
            callbacks => {
                'valid object' => sub
                {
                    my $obj = shift;
                    blessed($obj) && $obj->isa('DateTime');
                }
            },
        },
    });
}

sub _init_vars
{
    my $self = shift;

    delete @$self{qw(keyword modified postprocess)};
}

sub parse_datetime
{
    my $self = shift;

    $self->_parse_init(@_);

    $self->{input_string} = $self->{date_string};

    my $date_string = $self->{date_string};

    $self->_rewrite(\$date_string);

    my ($formatted) = $date_string =~ $self->{data}->__regexes('format');
    my %count = $self->_count_separators($formatted);

    $self->{tokens} = [];
    $self->{traces} = [];

    if ($self->_check_formatted('ymd', \%count)) {
        my $dt = $self->_parse_formatted_ymd($date_string, \%count);
        return $dt if blessed($dt);
    }
    elsif ($self->_check_formatted('md', \%count)) {
        my $dt = $self->_parse_formatted_md($date_string);
        return $dt if blessed($dt);

        if ($self->{Prefer_future}) {
            $self->_advance_future('md');
        }
    }
    elsif ($date_string =~ /^([+-]) (\d+?) ([a-zA-Z]+)$/x) {
        my ($prefix, $value, $unit) = ($1, $2, lc $3);

        my %methods = (
            '+' => '_add',
            '-' => '_subtract',
        );
        my $method = $methods{$prefix};

        if (none { $unit =~ /^${_}s?$/ } @{$self->{data}->__units('ordered')}) {
            $self->_set_failure;
            $self->_set_error("(invalid unit)");
            return $self->_get_datetime_object;
        }
        $self->$method($unit => $value);

        $self->_set_valid_exp;
    }
    elsif ($date_string =~ /^\d{14}$/) {
        my %args;
        @args{qw(year month day hour minute second)} = $date_string =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/;

        my $valid_date = $self->_check_date(map $args{$_}, qw(year month day));
        my $valid_time = $self->_check_time(map $args{$_}, qw(hour minute second));

        if (not $valid_date && $valid_time) {
            my $type = !$valid_date ? 'date' : 'time';
            $self->_set_failure;
            $self->_set_error("(invalid $type)");
            return $self->_get_datetime_object;
        }

        $self->_set(%args);

        $self->_set_valid_exp;
    }
    else {
        @{$self->{tokens}} = split /\s+/, $date_string;
        $self->{data}->__init('tokens')->($self);
        $self->{count}{tokens} = @{$self->{tokens}};

        $self->_process;
    }

    my $trace = $self->_trace_string;
    if (defined $trace) {
        @{$self->{traces}} = $trace;
    }

    return $self->_get_datetime_object;
}

sub _params_init
{
    my $self = shift;
    my $params = pop;

    if (@_ > 1) {
        validate(@_, { string => { type => SCALAR }});
        my %opts = @_;
        foreach my $opt (keys %opts) {
            ${$params->{$opt}} = $opts{$opt};
        }
    }
    else {
        validate_pos(@_, { type => SCALAR });
        (${$params->{string}}) = @_;
    }

    ${$params->{string}} = do {
        local $_ = ${$params->{string}};
        s/^\s+//;
        s/\s+$//;
        $_;
    };
}

sub _parse_init
{
    my $self = shift;

    $self->_params_init(@_, { string => \$self->{date_string} });

    my $set_datetime = sub
    {
        my ($method, $args) = @_;

        if (exists $self->{Datetime} && $method eq 'now') {
            $self->{datetime} = dclone($self->{Datetime});
        }
        else {
            $self->{datetime} = DateTime->$method(
                time_zone => $self->{Time_zone},
                %$args,
            );
        }
    };

    if ($self->{running_tests}) {
        $self->{datetime} = $self->{datetime_test}->clone;
    }
    else {
        $set_datetime->('now', {});
    }

    $self->_init_vars;

    $self->_unset_failure;
    $self->_unset_error;
    $self->_unset_valid_exp;
    $self->_unset_trace;
}

sub parse_datetime_duration
{
    my $self = shift;

    my $duration_string;
    $self->_params_init(@_, { string => \$duration_string });
    my $timespan_sep = $self->{data}->__timespan('literal');

    my @date_strings = $duration_string =~ /\b $timespan_sep \b/ix
      ? do { $self->{duration} = true;
             split /\s+ $timespan_sep \s+/ix, $duration_string }
      : do { $self->{duration} = false;
             ($duration_string) };

    my $max = 2;

    my $shrinked = false;
    if (@date_strings > $max) {
        my $offset = $max;
        splice (@date_strings, $offset);
        $shrinked = true;
    }

    $self->_pre_duration(\@date_strings);
    $self->{state} = {};

    my (@queue, @traces);
    foreach my $date_string (@date_strings) {
        push @queue, $self->parse_datetime($date_string);
        $self->_save_state(
            valid_expression => $self->_get_valid_exp,
            failure          => $self->_get_failure,
            error            => $self->_get_error,
        );
        if (@{$self->{traces}}) {
            push @traces, $self->{traces}[0];
        }
    }

    $self->_post_duration(\@queue, \@traces);
    $self->_restore_state;

    delete @$self{qw(duration insert state)};

    @{$self->{traces}} = @traces;
    $self->{input_string} = $duration_string;

    if ($shrinked) {
        $self->_set_failure;
        $self->_set_error("(limit of $max duration substrings exceeded)");
    }

    return @queue;
}

sub extract_datetime
{
    my $self = shift;

    my $extract_string;
    $self->_params_init(@_, { string => \$extract_string });

    my @expressions = $self->_extract_expressions($extract_string);

    return wantarray ? @expressions : $expressions[0];
}

sub success
{
    my $self = shift;

    return ($self->_get_valid_exp && !$self->_get_failure) ? true : false;
}

sub error
{
    my $self = shift;

    return '' if $self->success;

    my $error  = "'$self->{input_string}' does not parse ";
       $error .= $self->_get_error || '(perhaps you have some garbage?)';

    return $error;
}

sub trace
{
    my $self = shift;

    return @{$self->{traces}};
}

sub _process
{
    my $self = shift;

    my %opts;

    if (!exists $self->{lookup}) {
        foreach my $keyword (keys %{$self->{data}->__grammar('')}) {
            my $count = scalar @{$self->{data}->__grammar($keyword)->[0]};
            push @{$self->{lookup}{$count}}, [ $keyword, false ];
            if ($self->_expand_for($keyword)) {
                push @{$self->{lookup}{$count + 1}}, [ $keyword, true ];
            }
        }
    }

    PARSE: foreach my $lookup (@{$self->{lookup}{$self->{count}{tokens}} || []}) {
        my ($keyword, $expandable) = @$lookup;

        my @grammar = @{$self->{data}->__grammar($keyword)};
        my $types = shift @grammar;

        @grammar = map [ $types, $_ ], @grammar;
        @grammar = $self->_expand($keyword, \@grammar) if $expandable;

        foreach my $entry (@grammar) {
            my ($types, $expression) = @$entry;
            my $valid_expression = true;
            my $definition = $expression->[0];
            my @positions = sort {$a <=> $b} keys %$definition;
            my (%first_stack, %rest_stack);
            foreach my $pos (@positions) {
                if ($types->[$pos] eq 'SCALAR') {
                    if (defined $definition->{$pos}) {
                        if (${$self->_token($pos)} =~ /^$definition->{$pos}$/i) {
                            next;
                        }
                        else {
                            $valid_expression = false;
                            last;
                        }
                    }
                }
                elsif ($types->[$pos] eq 'REGEXP') {
                    if (my @captured = ${$self->_token($pos)} =~ $definition->{$pos}) {
                        $first_stack{$pos} = shift @captured;
                        $rest_stack{$pos} = [ @captured ];
                        next;
                    }
                    else {
                        $valid_expression = false;
                        last;
                    }
                }
                else {
                    die "grammar error at keyword \"$keyword\" within $self->{grammar_class}: ",
                        "unknown type $types->[$pos]\n";
                }
            }
            if ($valid_expression && @{$expression->[2]}) {
                my $i;
                foreach my $check (@{$expression->[2]}) {
                    my @pos = @{$expression->[1][$i++]};
                    my $error;
                    $valid_expression &= $check->(\%first_stack, \%rest_stack, \@pos, \$error);
                    unless ($valid_expression) {
                        $self->_set_error("($error)");
                        last;
                    }
                }
            }
            if ($valid_expression) {
                $self->_set_valid_exp;
                my @truncate_to = @{$expression->[6]->{truncate_to} || []};
                my $i = 0;
                foreach my $positions (@{$expression->[3]}) {
                    my ($c, @values);
                    foreach my $pos (@$positions) {
                        my $index = ref $pos eq 'HASH' ? (keys %$pos)[0] : $pos;
                        $values[$c++] = ref $pos
                          ? $index eq 'VALUE'
                            ? $pos->{$index}
                            : $self->SUPER::_helper($pos->{$index}, $first_stack{$index})
                          : exists $first_stack{$index}
                            ? $first_stack{$index}
                            : ${$self->_token($index)};
                    }
                    my $worker = "SUPER::$expression->[5]->[$i]";
                    $self->$worker(@values, $expression->[4]->[$i++]);
                    $self->_truncate(shift @truncate_to);
                }
                %opts = %{$expression->[6]};
                $self->{keyword} = $keyword;
                last PARSE;
            }
        }
    }

    $self->_post_process(%opts);
}

sub _truncate
{
    my $self = shift;
    my ($truncate_to) = @_;

    return unless defined $truncate_to;

    my @truncate_to = map { $_ =~ /_/ ? split /_/, $_ : $_ } $truncate_to;
    my $i = 0;
    my @units = @{$self->{data}->__units('ordered')};
    my %indexes = map { $_ => $i++ } @units;
    foreach my $unit (@truncate_to) {
        my $index = $indexes{$unit} - 1;
        if (defined $units[$index] && !exists $self->{modified}{$units[$index]}) {
            $self->{datetime}->truncate(to => $unit);
            last;
        }
    }
}

sub _post_process
{
    my $self = shift;
    my %opts = @_;

    delete $opts{truncate_to};

    if ($self->{Prefer_future} &&
        (exists $opts{prefer_future} && $opts{prefer_future})
    ) {
        $self->_advance_future;
    }
}

sub _advance_future
{
    my $self = shift;
    my %advance = map { $_ => true } @_;

    my %modified = map { $_ => true } keys %{$self->{modified}};
    my $token_contains = sub
    {
        my ($identifier) = @_;
        return any {
          my $data = $_;
          any {
            my $token = $_;
            $token =~ /^$data$/i;
          } @{$self->{tokens}}
        } @{$self->{data}->{$identifier}};
    };

    if ((all { /^(?:second|minute|hour)$/ } keys %modified)
        && (exists $self->{modified}{hour} && $self->{modified}{hour} == 1)
        && $self->{datetime}->hour < DateTime->now(time_zone => $self->{Time_zone})->hour
    ) {
        $self->{postprocess}{day} = 1;
    }
    elsif ($token_contains->('weekdays_all')
        && (exists $self->{modified}{day} && $self->{modified}{day} == 1)
        && ($self->_Day_of_Week(map $self->{datetime}->$_, qw(year month day))
         < DateTime->now(time_zone => $self->{Time_zone})->wday)
    ) {
        $self->{postprocess}{day} = 7;
    }
    elsif (($token_contains->('months_all') || $advance{md})
        && (all { /^(?:day|month)$/ } keys %modified)
        && (exists $self->{modified}{month} && $self->{modified}{month} == 1)
        && (exists $self->{modified}{day}
              ? $self->{modified}{day} == 1
                ? true : false
              : true)
        && ($self->{datetime}->day_of_year < DateTime->now->day_of_year)
    ) {
        $self->{postprocess}{year} = 1;
    }
}

sub _token
{
    my $self = shift;
    my ($pos) = @_;

    my $str = '';
    my $token = $self->{tokens}->[0 + $pos];

    return defined $token
      ? \$token
      : \$str;
}

sub _register_trace  { push @{$_[0]->{trace}}, (caller(1))[3] }
sub _unset_trace     { @{$_[0]->{trace}} = ()                 }

sub _get_error       { $_[0]->{error}         }
sub _set_error       { $_[0]->{error} = $_[1] }
sub _unset_error     { $_[0]->{error} = undef }

sub _get_failure     { $_[0]->{failure}         }
sub _set_failure     { $_[0]->{failure} = true  }
sub _unset_failure   { $_[0]->{failure} = false }

sub _get_valid_exp   { $_[0]->{valid_expression}         }
sub _set_valid_exp   { $_[0]->{valid_expression} = true  }
sub _unset_valid_exp { $_[0]->{valid_expression} = false }

sub _get_datetime_object
{
    my $self = shift;

    my $dt = DateTime->new(
        time_zone => $self->{datetime}->time_zone,
        year      => $self->{datetime}->year,
        month     => $self->{datetime}->month,
        day       => $self->{datetime}->day_of_month,
        hour      => $self->{datetime}->hour,
        minute    => $self->{datetime}->minute,
        second    => $self->{datetime}->second,
    );

    foreach my $unit (keys %{$self->{postprocess}}) {
        $dt->add("${unit}s" => $self->{postprocess}{$unit});
    }

    return $dt;
}

# solely for testing purpose
sub _set_datetime
{
    my $self = shift;
    my ($time, $tz) = @_;

    $self->{datetime_test} = DateTime->new(
        time_zone => $tz || 'floating',
        %$time,
    );
    $self->{running_tests} = true;
}

1;
__END__

=head1 NAME

DateTime::Format::Natural - Create machine readable date/time with natural parsing logic

=head1 SYNOPSIS

 use DateTime::Format::Natural;

 $parser = DateTime::Format::Natural->new;

 $date_string  = $parser->extract_datetime($extract_string);
 @date_strings = $parser->extract_datetime($extract_string);

 $dt = $parser->parse_datetime($date_string);
 @dt = $parser->parse_datetime_duration($date_string);

 if ($parser->success) {
     # operate on $dt/@dt, for example:
     printf("%02d.%02d.%4d %02d:%02d:%02d\n", $dt->day,
                                              $dt->month,
                                              $dt->year,
                                              $dt->hour,
                                              $dt->min,
                                              $dt->sec);
 } else {
     warn $parser->error;
 }

 @traces = $parser->trace;

=head1 DESCRIPTION

C<DateTime::Format::Natural> takes a string with a human readable date/time and creates a
machine readable one by applying natural parsing logic.

=head1 CONSTRUCTOR

=head2 new

Creates a new C<DateTime::Format::Natural> object. Arguments to C<new()> are options and
not necessarily required.

 $parser = DateTime::Format::Natural->new(
           datetime      => DateTime->new(...),
           lang          => 'en',
           format        => 'mm/dd/yy',
           prefer_future => '[0|1]',
           time_zone     => 'floating',
           daytime       => { morning   => 06,
                              afternoon => 13,
                              evening   => 20,
                            },
 );

=over 4

=item * C<datetime>

Overrides the present now with a L<DateTime> object provided.

=item * C<lang>

Contains the language selected, currently limited to C<en> (english).
Defaults to 'C<en>'.

=item * C<format>

Specifies the format of numeric dates, defaults to 'C<d/m/y>'.

=item * C<prefer_future>

Turns ambiguous weekdays/months to their future relatives. Accepts a boolean,
defaults to false.

=item * C<time_zone>

The time zone to use when parsing and for output. Accepts any time zone
recognized by L<DateTime>. Defaults to 'floating'.

=item * C<daytime>

An anonymous hash reference consisting of customized daytime hours,
which may be selectively changed.

=back

=head1 METHODS

=head2 parse_datetime

Returns a L<DateTime> object constructed from a human readable date/time string.

 $dt = $parser->parse_datetime($date_string);
 $dt = $parser->parse_datetime(string => $date_string);

=over 4

=item * C<string>

The date string.

=back

=head2 parse_datetime_duration

Returns one or two L<DateTime> objects constructed from a human readable
date/time string which may contain timespans/durations. I<Same> interface
and options as C<parse_datetime()>, but should be explicitly called in
list context.

 @dt = $parser->parse_datetime_duration($date_string);
 @dt = $parser->parse_datetime_duration(string => $date_string);

=head2 extract_datetime

Returns parsable date/time substrings (also known as expressions) extracted
from the string provided; in scalar context only the first parsable substring
is returned, whereas in list context all parsable substrings are returned.
Each extracted substring can then be passed to the C<parse_datetime()>/
C<parse_datetime_duration()> methods.

 $date_string  = $parser->extract_datetime($extract_string);
 @date_strings = $parser->extract_datetime($extract_string);
 # or
 $date_string  = $parser->extract_datetime(string => $extract_string);
 @date_strings = $parser->extract_datetime(string => $extract_string);

=head2 success

Returns a boolean indicating success or failure for parsing the date/time
string given.

=head2 error

Returns the error message if the parsing did not succeed.

=head2 trace

Returns one or two strings with the grammar keyword for the valid
expression parsed, traces of methods which were called within the Calc
class and a summary how often certain units have been modified. More than
one string is commonly returned for durations. Useful as a debugging aid.

=head1 GRAMMAR

The grammar handling has been rewritten to be easily extendable and hence
everybody is encouraged to propose sensible new additions and/or changes.

See the classes C<DateTime::Format::Natural::Lang::[language_code]> if
you're intending to hack a bit on the grammar guts.

=head1 EXAMPLES

See the classes C<DateTime::Format::Natural::Lang::[language_code]> for an
overview of currently valid input.

=head1 BUGS & CAVEATS

C<parse_datetime()>/C<parse_datetime_duration()> always return one or two
DateTime objects regardless whether the parse was successful or not. In
case no valid expression was found or a failure occurred, an unaltered
DateTime object with its initial values (most often the "current" now) is
likely to be returned. It is therefore recommended to use C<success()> to
assert that the parse did succeed (at least, for common uses), otherwise
the absence of a parse failure cannot be guaranteed.

C<parse_datetime()> is not capable of handling durations.

=head1 CREDITS

Thanks to Tatsuhiko Miyagawa for the initial inspiration. See Miyagawa's journal
entry L<http://use.perl.org/~miyagawa/journal/31378> for more information.

Furthermore, thanks to (in order of appearance) who have contributed
valuable suggestions and patches:

 Clayton L. Scott
 Dave Rolsky
 CPAN Author 'SEKIMURA'
 mike (pulsation)
 Mark Stosberg
 Tuomas Jormola
 Cory Watson
 Urs Stotz
 Shawn M. Moore
 Andreas J. König
 Chia-liang Kao
 Jonny Schulz
 Jesse Vincent
 Jason May
 Pat Kale
 Ankur Gupta
 Alex Bowley
 Elliot Shank
 Anirvan Chatterjee
 Michael Reddick
 Christian Brink
 Giovanni Pensa
 Andrew Sterling Hanenkamp
 Eric Wilhelm
 Kevin Field
 Wes Morgan
 Vladimir Marek
 Rod Taylor
 Tim Esselens
 Colm Dougan
 Chifung Fan
 Xiao Yafeng
 Roman Filippov

=head1 SEE ALSO

L<dateparse>, L<DateTime>, L<Date::Calc>, L<http://datetime.perl.org>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
