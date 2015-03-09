package DateTime::Format::Natural::Calc;

use strict;
use warnings;
use base qw(
    DateTime::Format::Natural::Compat
    DateTime::Format::Natural::Utils
    DateTime::Format::Natural::Wrappers
);

our $VERSION = '1.39';

use constant MORNING   => '08';
use constant AFTERNOON => '14';
use constant EVENING   => '20';

sub _no_op
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
}

sub _ago_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    $self->_subtract($opts->{unit} => shift);
}

sub _now_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($value, $when) = @_;
    $self->_add_or_subtract({
        when  => $when,
        unit  => $opts->{unit},
        value => $value,
    });
}

sub _daytime_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($daytime) = @_;
    my %lookup = (
        0 => 'morning',
        1 => 'afternoon',
        2 => 'evening',
    );
    $daytime = $lookup{$daytime};
    my %daytimes = (
        morning   => MORNING,
        afternoon => AFTERNOON,
        evening   => EVENING,
    );
    my $hour = exists $self->{Daytime}{$daytime}
      ? $self->{Daytime}{$daytime}
      : $daytimes{$daytime};
    if ($self->_valid_time(hour => $hour)) {
        $self->_set(hour => $hour);
    }
}

sub _daytime
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($hour) = @_;
    $hour += $opts->{hours} || 0;
    if ($self->_valid_time(hour => $hour)) {
        $self->_set(hour => $hour);
    }
}

sub _hourtime_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($value, $when) = @_;
    my $hours = $opts->{hours} || 0;
    if ($self->_valid_time(hour => $hours)) {
        $self->_set(hour => $hours);
        $self->_add_or_subtract({
            when  => $when,
            unit  => 'hour',
            value => $value,
        });
    }
}

sub _month_day
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($day, $month) = @_;
    if ($self->_valid_date(month => $month, day => $day)) {
        $self->_set(
            month => $month,
            day   => $day,
        );
    }
}

sub _unit_date
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($value) = @_;
    $self->{datetime}->set(day => 1) if $opts->{unit} eq 'month';
    if ($self->_valid_date($opts->{unit} => $value)) {
        $self->_set($opts->{unit} => $value);
    }
}

sub _weekday
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($day) = @_;
    if ($day > $self->{datetime}->wday) {
        $self->_add(day => ($day - $self->{datetime}->wday));
    }
    else {
        $self->_subtract(day => ($self->{datetime}->wday - $day));
    }
}

sub _count_day_variant_week
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($when, $day) = @_;
    my %days = (
        -1 => ($self->{datetime}->wday + (7 - $day)),
         0 => ($day - $self->{datetime}->wday),
         1 => (7 - $self->{datetime}->wday + $day),
    );
    $self->_add_or_subtract({
        when  => ($when == 0) ? 1 : $when,
        unit  => 'day',
        value => $days{$when},
    });
}

sub _count_day_variant_month
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($when, $day) = @_;
    if ($self->_valid_date(day => $day)) {
        $self->_add(month => $when);
        $self->_set(day => $day);
    }
}

sub _unit_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($when) = @_;
    $self->_add_or_subtract({
        when  => $when,
        unit  => $opts->{unit},
        value => 1,
    });
}

sub _count_month_variant_year
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($when, $month) = @_;
    if ($self->_valid_date(month => $month)) {
        $self->_add(year => $when);
        $self->_set(month => $month);
    }
}

sub _in_count_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    $self->_add_or_subtract($opts->{unit} => shift);
}

sub _month_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($when, $month) = @_;
    if ($self->_valid_date(month => $month)) {
        $self->_add(year => $when);
        $self->_set(month => $month);
    }
}

sub _count_weekday_variant_month
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($when, $count, $day, $month) = @_;
    my $year;
    local $@;
    eval {
        ($year, $month, $day) =
          $self->_Nth_Weekday_of_Month_Year(
              $self->{datetime}->year + $when,
              defined $month
                ? $month
                : $self->{datetime}->month,
              $day,
              $count,
          );
    };
    if (!$@
        and defined $year && defined $month && defined $day
        and $self->_check_date($year, $month, $day)
    ) {
        $self->_set(
            year  => $year,
            month => $month,
            day   => $day,
        );
    }
    else {
        $self->_set_failure;
        $self->_set_error("(date is not valid)");
    }
}

sub _daytime_hours_variant
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($hours, $when, $days) = @_;
    my %values = (
        -1 => { day => ($days - 1), hours => (24 - $hours) },
         1 => { day => $days,       hours => (0  + $hours) },
    );
    if ($self->_valid_time(hour => $values{$when}->{hours})) {
        $self->_add(day => $values{$when}->{day});
        $self->_set(hour => $values{$when}->{hours});
    }
}

# wrapper for <time> AM/PM
sub _at
{
    my $self = shift;
    $self->_register_trace;
    $self->_at_time(@_);
}

# wrapper for <time>
sub _time
{
    my $self = shift;
    $self->_register_trace;
    $self->_at_time(@_);
}

sub _at_time
{
    my $self = shift;
    my $opts = pop;
    my ($time) = @_;
    my @units = qw(hour minute second);
    my %values = map { shift @units => $_ } split /:/, $time;
    if ($self->_valid_time(%values)) {
        $self->_set(%values);
    }
}

sub _count_yearday_variant_year
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($day, $when) = @_;
    my ($year, $month);
    ($year, $month, $day) = $self->_Add_Delta_Days($self->{datetime}->year, $day);
    $self->_set(
        year  => $year + $when,
        month => $month,
        day   => $day,
    );
}

sub _count_weekday
{
    my $self = shift;
    $self->_count_weekday_variant_month(0, @_[0,1], undef, $_[-1]);
}

sub _day_month_year
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($day, $month, $year) = @_;
    if ($self->_valid_date(year => $year, month => $month, day => $day)) {
        $self->_set(
            year  => $year,
            month => $month,
            day   => $day,
        );
    }
}

sub _count_weekday_from_now
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($count, $day) = @_;
    my $wday = $self->{datetime}->wday;
    $self->_add(day => ($count - 1) * 7 +
        (($wday < $day)
          ? $day - $wday
          : (7 - $wday) + $day)
    );
}

sub _final_weekday_in_month
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($wday, $month) = @_;
    my $days = $self->_Days_in_Month($self->{datetime}->year, $month);
    my ($year, $day);
    ($year, $month, $day) = $self->_Nth_Weekday_of_Month_Year(
        $self->{datetime}->year,
        $month,
        $wday,
        1,
    );
    while ($day <= $days - 7) {
        $day += 7;
    }
    $self->_set(
        year  => $year,
        month => $month,
        day   => $day,
    );
}

sub _first_last_day_unit
{
    my $self = shift;
    $self->_register_trace;
    my $opts = pop;
    my ($year, $month, $day) = do {
        @_ >= 3 ? @_ : (undef, @_);
    };
    $year ||= $self->{datetime}->year;
    unless (defined $day) {
        $day = $self->_Days_in_Month($year, $month);
    }
    $self->_set(
        year  => $year,
        month => $month,
        day   => $day,
    );
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Calc - Basic calculations

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Calc> class defines the worker methods.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
