package DateTime::Format::Natural::Helpers;

use strict;
use warnings;
use base qw(Exporter);
use boolean qw(true false);

use constant REAL_FLAG => true;
use constant VIRT_FLAG => false;

our ($VERSION, @EXPORT_OK, %flag);

$VERSION = '0.06';
@EXPORT_OK = qw(%flag);

my @flags = (
    { weekday_name      => REAL_FLAG },
    { weekday_num       => REAL_FLAG },
    { month_name        => REAL_FLAG },
    { month_num         => REAL_FLAG },
    { time_am           => REAL_FLAG },
    { time_pm           => REAL_FLAG },
    { last_this_next    => VIRT_FLAG },
    { yes_today_tom     => VIRT_FLAG },
    { noon_midnight     => VIRT_FLAG },
    { morn_aftern_even  => VIRT_FLAG },
    { before_after_from => VIRT_FLAG },
);

{
    my $i;
    %flag = map { (keys %$_)[0] => $i++ } @flags;
}

sub _helper
{
    my $self = shift;
    my ($flags, $string) = @_;

    foreach my $flag (@$flags) {
        my $name = (keys %{$flags[$flag]})[0];
        if ($flags[$flag]->{$name}) {
            my $helper = "_$name";
            $self->$helper(\$string);
        }
        else {
            $string = $self->{data}->{conversion}->{$name}->{lc $string};
        }
    }

    return $string;
}

sub _weekday_name
{
    my $self = shift;
    my ($arg) = @_;

    my $helper = $self->{data}->{helpers};

    if ($$arg =~ $helper->{suffix}) {
        $$arg =~ s/$helper->{suffix}//;
    }
    $helper->{normalize}->($arg);
    if ($helper->{abbreviated}->($arg)) {
        $$arg = $self->{data}->{weekdays_abbrev}->{$$arg};
    }
}

sub _weekday_num
{
    my $self = shift;
    my ($arg) = @_;

    $$arg = $self->_Decode_Day_of_Week($$arg);
}

sub _month_name
{
    my $self = shift;
    my ($arg) = @_;

    my $helper = $self->{data}->{helpers};

    $helper->{normalize}->($arg);
    if ($helper->{abbreviated}->($arg)) {
        $$arg = $self->{data}->{months_abbrev}->{$$arg};
    }
}

sub _month_num
{
    my $self = shift;
    my ($arg) = @_;

    $$arg = $self->_Decode_Month($$arg);
}

sub _time_am
{
    my $self = shift;
    my ($arg) = @_;

    $self->_time_meridiem($arg, 'am');
}

sub _time_pm
{
    my $self = shift;
    my ($arg) = @_;

    $self->_time_meridiem($arg, 'pm');
}

sub _time_meridiem
{
    my $self = shift;
    my ($time, $period) = @_;

    my ($hour) = split /:/, $$time;

    my %hours = (
        am => $hour - (($hour == 12) ? 12 :  0),
        pm => $hour + (($hour == 12) ?  0 : 12),
    );

    $$time =~ s/^ \d+? (?:(?=\:)|$)/$hours{$period}/x;
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Helpers - Various helper methods

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Helpers> class defines helper methods.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
