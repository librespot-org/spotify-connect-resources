package DateTime::Format::Natural::Rewrite;

use strict;
use warnings;

our $VERSION = '0.05';

sub _rewrite
{
    my $self = shift;
    my ($date_string) = @_;

    $self->_rewrite_regular($date_string);
    $self->_rewrite_aliases($date_string);
    $self->_rewrite_conditional($date_string);
}

sub _rewrite_regular
{
    my $self = shift;
    my ($date_string) = @_;

    $$date_string =~ tr/,//d;
    $$date_string =~ s/\s+?(am|pm)\b/$1/i;
}

sub _rewrite_conditional
{
    my $self = shift;
    my ($date_string) = @_;

    my $rewrite = $self->{data}->{rewrite};

    if ($$date_string =~ $rewrite->{at}{match}) {
        my $last_token = (split /\s+/, $$date_string)[-1];
        my @regexes = (
            (map $self->{data}->__RE($_), qw(time time_am time_pm)),
            $rewrite->{at}{daytime},
        );
        foreach my $regex (@regexes) {
            if ($last_token =~ $regex) {
                $$date_string  =~ s/$rewrite->{at}{subst}//;
                $$date_string .= ':00' if $$date_string =~ /\s+?\d{1,2}$/;
                last;
            }
        }
    }
}

sub _rewrite_aliases
{
    my $self = shift;
    my ($date_string) = @_;

    my $aliases = $self->{data}->{aliases};

    if ($$date_string =~ /\s+/) {
        foreach my $type (qw(words tokens)) {
            foreach my $alias (keys %{$aliases->{$type}}) {
                if ($alias =~ /^\w+$/) {
                    $$date_string =~ s/\b $alias \b/$aliases->{$type}{$alias}/ix;
                }
                else {
                    $$date_string =~ s/(?:^|(?<=\s)) $alias (?:(?=\s)|$)/$aliases->{$type}{$alias}/ix;
                }
            }
        }
    }
    else {
        foreach my $alias (keys %{$aliases->{words}}) {
            $$date_string =~ s/^ $alias $/$aliases->{words}{$alias}/ix;
        }
        foreach my $alias (keys %{$aliases->{short}}) {
            $$date_string =~ s/(?<=\d) $alias $/$aliases->{short}{$alias}/ix;
        }
    }
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Rewrite - Aliasing and rewriting of date strings

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

The C<DateTime::Format::Natural::Rewrite> class handles aliases and regular
rewrites of date strings.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
