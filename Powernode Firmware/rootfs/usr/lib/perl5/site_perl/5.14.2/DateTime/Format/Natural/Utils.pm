package DateTime::Format::Natural::Utils;

use strict;
use warnings;
use boolean qw(true false);

our $VERSION = '0.05';

sub _valid_date
{
    my $self = shift;
    return $self->_valid(@_,
        { units => [ qw(year month day) ],
          error => '(date is not valid)',
          type  => 'date',
        },
    );
}

sub _valid_time
{
    my $self = shift;
    return $self->_valid(@_,
        { units => [ qw(hour minute second) ],
          error => '(time is not valid)',
          type  => 'time',
        },
    );
}

sub _valid
{
    my $self = shift;
    my $opts = pop;
    my %values = @_;

    my %set = map { $_ => $self->{datetime}->$_ } @{$opts->{units}};

    while (my ($unit, $value) = each %values) {
        $set{$unit} = $value;
    }

    my $checker = '_check' . "_$opts->{type}";

    if ($self->$checker(map $set{$_}, @{$opts->{units}})) {
        return true;
    }
    else {
        $self->_set_failure;
        $self->_set_error($opts->{error});
        return false;
    }
}

sub _trace_string
{
    my $self = shift;

    my ($trace, $modified, $keyword) = map $self->{$_}, qw(trace modified keyword);

    $trace    ||= [];
    $modified ||= {};
    $keyword  ||= '';

    return undef unless (@$trace || %$modified || length $keyword);

    my $i;
    my %order = map { $_ => $i++ } @{$self->{data}->__units('ordered')};

    return join "\n", grep length, $keyword, @$trace,
      map { my $unit = $_; "$unit: $modified->{$unit}" }
      sort { $order{$a} <=> $order{$b} }
      keys %$modified;
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Utils - Handy utility methods

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Utils> class consists of utility methods.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
