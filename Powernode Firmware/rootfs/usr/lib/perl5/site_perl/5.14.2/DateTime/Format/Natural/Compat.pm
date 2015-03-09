package DateTime::Format::Natural::Compat;

use strict;
use warnings;
use boolean qw(true false);

use DateTime ();

our ($VERSION, $Pure);

$VERSION = '0.07';

BEGIN
{
    if (eval "require Date::Calc") {
        Date::Calc->import(qw(
            Add_Delta_Days
            Day_of_Week
            Days_in_Month
            Decode_Day_of_Week
            Decode_Month
            Nth_Weekday_of_Month_Year
            check_date
            check_time
        ));
        $Pure = false;
    }
    else {
        $Pure = true;
    }
}

sub _Add_Delta_Days
{
    my $self = shift;

    if ($Pure) {
        my ($year, $day) = @_;
        my $dt = DateTime->from_day_of_year(year => $year, day_of_year => $day);
        return ($dt->year, $dt->month, $dt->mday);
    }
    else {
        my ($year, $day) = @_;
        return Add_Delta_Days($year, 1, 1, $day - 1);
    }
}

sub _Day_of_Week
{
    my $self = shift;

    if ($Pure) {
        return $self->{datetime}->wday;
    }
    else {
        return Day_of_Week(@_);
    }
}

sub _Days_in_Month
{
    my $self = shift;

    if ($Pure) {
        my ($year, $month) = @_;
        my $dt = DateTime->last_day_of_month(year => $year, month => $month);
        return $dt->day;
    }
    else {
        return Days_in_Month(@_);
    }
}

sub _Decode_Day_of_Week
{
    my $self = shift;

    if ($Pure) {
        my ($day) = @_;
        return $self->{data}->{weekdays}->{$day};
    }
    else {
        return Decode_Day_of_Week(@_);
    }
}

sub _Decode_Month
{
    my $self = shift;

    if ($Pure) {
        my ($month) = @_;
        return $self->{data}->{months}->{$month};
    }
    else {
        return Decode_Month(@_);
    }
}

sub _Nth_Weekday_of_Month_Year
{
    my $self = shift;

    if ($Pure) {
        my ($year, $month, $weekday, $count) = @_;
        my $dt = $self->{datetime}->clone;
        $dt->set_year($year);
        $dt->set_month($month);
        $dt->set_day(1);
        $dt->set_day($dt->day + 1)
          while ($weekday ne $dt->dow);
        $dt->set_day($dt->day + 7 * ($count - 1));
        return ($dt->year, $dt->month, $dt->day);
    }
    else {
        return Nth_Weekday_of_Month_Year(@_);
    }
}

sub _check_date
{
    my $self = shift;

    if ($Pure) {
        my ($year, $month, $day) = @_;
        local $@;
        eval {
            my $dt = $self->{datetime}->clone;
            $dt->set(year => $year, month => $month, day => $day);
        };
        return !$@;
    }
    else {
        return check_date(@_);
    }
}

sub _check_time
{
    my $self = shift;

    if ($Pure) {
        my ($hour, $minute, $second) = @_;
        local $@;
        eval {
            my $dt = $self->{datetime}->clone;
            $dt->set(hour => $hour, minute => $minute, second => $second);
        };
        return !$@;
    }
    else {
        return check_time(@_);
    }
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Compat - Methods with more than one implementation

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Compat> class defines methods which must retain
more than one possible implementation due to compatibility issues on certain
platforms.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
