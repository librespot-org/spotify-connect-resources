package DateTime::Format::Natural::Extract;

use strict;
use warnings;
use base qw(DateTime::Format::Natural::Formatted);
use boolean qw(true false);

our $VERSION = '0.05';

sub _extract_expressions
{
    my $self = shift;
    my ($extract_string) = @_;

    $extract_string =~ s/^\s*[,;.]?//;
    $extract_string =~ s/[,;.]?\s*$//;

    while (my ($mark) = $extract_string =~ /([,;.])/cg) {
        my %patterns = (
            ',' => qr/(?!\d{4})/,
            ';' => qr/(?=\w)/,
            '.' => qr/(?=\w)/,
        );
        my $pattern = $patterns{$mark};
        $extract_string =~ s/\Q$mark\E \s+? $pattern/ [token] /x; # pretend punctuation marks are tokens
    }

    $self->_rewrite(\$extract_string);

    my @tokens = split /\s+/, $extract_string;
    my %entries = %{$self->{data}->__grammar('')};

    my @expressions;

    my %lengths;
    foreach my $keyword (keys %entries) {
        $lengths{$keyword} = @{$entries{$keyword}->[0]};
    }
    my ($seen_expression, %skip);
    do {
        $seen_expression = false;
        my $date_index;
        for (my $i = 0; $i < @tokens; $i++) {
            next if $skip{$i};
            if ($self->_check_for_date($tokens[$i], $i, \$date_index)) {
                last;
            }
        }
        OUTER:
        foreach my $keyword (sort { $lengths{$b} <=> $lengths{$a} } grep { $lengths{$_} <= @tokens } keys %entries) {
            my @grammar = @{$entries{$keyword}};
            my $types = shift @grammar;
            my $pos = 0;
            my @indexes;
            my $date_index;
            foreach my $expression (@grammar) {
                my $definition = $expression->[0];
                my $matched = false;
                for (my $i = 0; $i < @tokens; $i++) {
                    next if $skip{$i};
                    last unless defined $types->[$pos];
                    if ($self->_check_for_date($tokens[$i], $i, \$date_index)) {
                        next;
                    }
                    if ($types->[$pos] eq 'SCALAR' && defined $definition->{$pos} && $tokens[$i] =~ /^$definition->{$pos}$/i
                     or $types->[$pos] eq 'REGEXP'                                && $tokens[$i] =~   $definition->{$pos}
                    && (@indexes ? ($i - $indexes[-1] == 1) : true)
                    ) {
                        $matched = true;
                        push @indexes, $i;
                        $pos++;
                    }
                    elsif ($matched) {
                        last;
                    }
                }
                if (@indexes == $lengths{$keyword}
                && (defined $date_index ? ($indexes[0] - $date_index == 1) : true)
                ) {
                    my $expression = join ' ', (defined $date_index ? $tokens[$date_index] : (), @tokens[@indexes]);
                    my $start_index = defined $date_index ? $indexes[0] - 1 : $indexes[0];
                    push @expressions, [ [ $start_index, $indexes[-1] ], $expression ];
                    $skip{$_} = true foreach (defined $date_index ? $date_index : (), @indexes);
                    $seen_expression = true;
                    last OUTER;
                }
            }
        }
        if (defined $date_index && !$seen_expression) {
            push @expressions, [ [ ($date_index) x 2 ], $tokens[$date_index] ];
            $skip{$date_index} = true;
            $seen_expression = true;
        }
    } while ($seen_expression);

    return $self->_finalize_expressions(\@expressions, \@tokens);
}

sub _finalize_expressions
{
    my $self = shift;
    my ($expressions, $tokens) = @_;

    my $timespan_sep = $self->{data}->__timespan('literal');
    my @final_expressions;

    my @duration_indexes;
    foreach my $expression (sort { $a->[0][0] <=> $b->[0][0] } @$expressions) {
        my $prev = $expression->[0][0] - 1;
        my $next = $expression->[0][1] + 1;

        if (defined $tokens->[$next] && $tokens->[$next] =~ /^$timespan_sep$/i) {
            if (@final_expressions   && $tokens->[$prev] !~ /^$timespan_sep$/i) {
                @duration_indexes = ();
            }
            push @duration_indexes, ($expression->[0][0] .. $expression->[0][1], $next);
        }
        elsif (defined $tokens->[$prev] && $tokens->[$prev] =~ /^$timespan_sep$/i) {
            push @duration_indexes, ($expression->[0][0] .. $expression->[0][1]);

            push @final_expressions, join ' ', @$tokens[@duration_indexes];
            @duration_indexes = ();
        }
        else {
            push @final_expressions, $expression->[1];
        }
    }

    my $exclude = sub { $_[0] =~ /^\d{1,2}$/ };

    return grep !$exclude->($_), @final_expressions;
}

sub _check_for_date
{
    my $self = shift;
    my ($token, $index, $date_index) = @_;

    my ($formatted) = $token =~ $self->{data}->__regexes('format');
    my %count = $self->_count_separators($formatted);
    if ($self->_check_formatted('ymd', \%count)) {
        $$date_index = $index;
        return true;
    }
    else {
        return false;
    }
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Extract - Extract parsable expressions from strings

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

C<DateTime::Format::Natural::Extract> extracts expressions from strings to be
processed by the parse methods.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
