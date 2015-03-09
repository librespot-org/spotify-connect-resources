package DateTime::Format::Natural::Duration;

use strict;
use warnings;

use DateTime::Format::Natural::Duration::Checks;
use List::MoreUtils qw(all);

our $VERSION = '0.05';

sub _pre_duration
{
    my $self = shift;
    my ($date_strings) = @_;

    my $check_if = sub
    {
        my $sub   = shift;
        my $class = join '::', (__PACKAGE__, 'Checks');
        my $check = $class->can($sub) or die "$sub() not found in $class";

        return $check->($self->{data}->{duration}, $date_strings, @_);
    };

    my ($present, $extract, $adjust);

    if ($check_if->('for', \$present)) {
        @{$self->{insert}}{qw(datetime trace)} = do {
            my $dt = $self->parse_datetime($present);
            ($dt, $self->{traces}[0]);
        };
    }
    elsif ($check_if->('first_to_last', \$extract)) {
        if (my ($complete) = $date_strings->[1] =~ $extract) {
            $date_strings->[0] .= " $complete";
        }
    }
    elsif ($check_if->('from_count_to_count', \$extract, \$adjust)) {
        if (my ($complete) = $date_strings->[0] =~ $extract) {
            $adjust->($date_strings, $complete);
        }
    }
}

sub _post_duration
{
    my $self = shift;
    my ($queue, $traces) = @_;

    my %assign = (
        datetime => $queue,
        trace    => $traces,
    );
    if (all { exists $self->{insert}{$_} } keys %assign) {
        unshift @{$assign{$_}}, $self->{insert}{$_} foreach keys %assign;
    }
}

sub _save_state
{
    my $self = shift;
    my %args = @_;

    return if %{$self->{state}};

    unless ($args{valid_expression}) {
        %{$self->{state}} = %args;
    }
}

sub _restore_state
{
    my $self = shift;

    my %state = %{$self->{state}};

    if (%state) {
        $state{valid_expression}
          ? $self->_set_valid_exp
          : $self->_unset_valid_exp;

        $state{failure}
          ? $self->_set_failure
          : $self->_unset_failure;

        defined $state{error}
          ? $self->_set_error($state{error})
          : $self->_unset_error;
    }
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Duration - Duration hooks and state handling

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Duration> class contains code to alter
tokens before parsing and to insert DateTime objects in the resulting
queue. Furthermore, there's code to save the state of the first failing
parse and restore it after the duration has been processed.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
