package DateTime::Format::Natural::Expand;

use strict;
use warnings;
use boolean qw(true false);

use Clone qw(clone);
use DateTime::Format::Natural::Helpers qw(%flag);

our $VERSION = '0.02';

my %data = (
    time => {
        4 => {},
        5 => '_time',
        6 => { truncate_to => [q(hour_minute)] },
    },
    time_min => {
        4 => {},
        5 => '_time',
        6 => { truncate_to => [q(minute)] },
    },
    time_am => {
        2 => 'meridiem',
        3 => $flag{time_am},
        4 => {},
        5 => '_at',
        6 => { truncate_to => [q(hour_minute)] },
    },
    time_pm => {
        2 => 'meridiem',
        3 => $flag{time_pm},
        4 => {},
        5 => '_at',
        6 => { truncate_to => [q(hour_minute)] },
    },
);

my %expand_prefix = (
    date_literal_variant        => [ qw(     time_min time_am time_pm) ],
    week_variant                => [ qw(     time_min time_am time_pm) ],
    month_variant               => [ qw(     time_min time_am time_pm) ],
    year_variant                => [ qw(     time_min time_am time_pm) ],
    weekday_variant_week        => [ qw(time          time_am time_pm) ],
    variant_week_weekday        => [ qw(time          time_am time_pm) ],
    final_weekday_in_month      => [ qw(time          time_am time_pm) ],
    month_day                   => [ qw(     time_min time_am time_pm) ],
    day_month_variant_year      => [ qw(     time_min time_am time_pm) ],
    day_month_year_ago          => [ qw(     time_min time_am time_pm) ],
    count_weekday               => [ qw(     time_min time_am time_pm) ],
    count_yearday               => [ qw(     time_min time_am time_pm) ],
    count_weekday_from_now      => [ qw(     time_min time_am time_pm) ],
    count_day_variant_week      => [ qw(     time_min time_am time_pm) ],
    count_day_variant_month     => [ qw(     time_min time_am time_pm) ],
    count_month_variant_year    => [ qw(     time_min time_am time_pm) ],
    count_weekday_variant_month => [ qw(     time_min time_am time_pm) ],
    count_weekday_in_month      => [ qw(     time_min time_am time_pm) ],
    count_yearday_variant_year  => [ qw(     time_min time_am time_pm) ],
);
my %expand_suffix = (
    date_literal_variant        => [ qw(     time_min time_am time_pm) ],
    week_variant                => [ qw(     time_min time_am time_pm) ],
    month_variant               => [ qw(     time_min time_am time_pm) ],
    year_variant                => [ qw(     time_min time_am time_pm) ],
    weekday_variant_week        => [ qw(time          time_am time_pm) ],
    variant_week_weekday        => [ qw(time          time_am time_pm) ],
    final_weekday_in_month      => [ qw(time          time_am time_pm) ],
    day_month_variant_year      => [ qw(     time_min time_am time_pm) ],
    day_month_year_ago          => [ qw(     time_min time_am time_pm) ],
    count_weekday               => [ qw(     time_min time_am time_pm) ],
    count_yearday               => [ qw(     time_min time_am time_pm) ],
    count_weekday_from_now      => [ qw(     time_min time_am time_pm) ],
    count_day_variant_week      => [ qw(     time_min time_am time_pm) ],
    count_day_variant_month     => [ qw(     time_min time_am time_pm) ],
    count_month_variant_year    => [ qw(     time_min time_am time_pm) ],
    count_weekday_variant_month => [ qw(     time_min time_am time_pm) ],
    count_weekday_in_month      => [ qw(     time_min time_am time_pm) ],
    count_yearday_variant_year  => [ qw(     time_min time_am time_pm) ],
);

my $save = sub
{
    my ($type, $target, @values) = @_;

    if ($type eq 'prefix') {
        unshift @$target, @values;
    }
    elsif ($type eq 'suffix') {
        push @$target, @values;
    }
};

sub _expand_for
{
    my $self = shift;
    my ($keyword) = @_;

    return (exists $expand_prefix{$keyword} || exists $expand_suffix{$keyword}) ? true : false;
}

sub _expand
{
    my $self = shift;
    my ($keyword, $grammar) = @_;

    my %expand = (
        prefix => \%expand_prefix,
        suffix => \%expand_suffix,
    );

    my (@expandable, @expansions);

    push @expandable, 'prefix' if exists $expand_prefix{$keyword};
    push @expandable, 'suffix' if exists $expand_suffix{$keyword};

    foreach my $type (@expandable) {
        my @elements = @{$expand{$type}->{$keyword}};

        foreach my $element (@elements) {
           foreach my $entry (@$grammar) {
                my $types = clone($entry->[0]);

                $save->($type, $types, 'REGEXP');

                my $new = clone($entry->[1]);

                if ($type eq 'prefix') {
                    my %definition;
                    while (my ($pos, $def) = each %{$new->[0]}) {
                        $definition{$pos + 1} = $def;
                    }
                    %{$new->[0]} = %definition;

                    my @indexes;
                    foreach my $aref (@{$new->[1]}) {
                        my @tmp = map $_ + 1, @$aref;
                        push @indexes, [ @tmp ];
                    }
                    @{$new->[1]} = @indexes;

                    my @flags;
                    foreach my $aref (@{$new->[3]}) {
                        my @tmp;
                        foreach my $value (@$aref) {
                            if (ref $value eq 'HASH') {
                                my %hash;
                                while (my ($key, $val) = each %$value) {
                                    $key++ if $key =~ /^\d+$/;
                                    $hash{$key} = $val;
                                }
                                push @tmp, { %hash };
                            }
                            else {
                                push @tmp, $value + 1;
                            }
                        }
                        push @flags, [ @tmp ];
                    }
                    @{$new->[3]} = @flags;
                }

                my %indexes = (
                    prefix => 0,
                    suffix => scalar keys %{$new->[0]},
                );

                my $i = $indexes{$type};

                $new->[0]->{$i} = $self->{data}->__RE($element);

                if (exists $data{$element}->{2}) {
                    $save->($type, $new->[1], [ $i ]);
                    $save->($type, $new->[2], $self->{data}->__extended_checks($data{$element}->{2}));
                }

                push @{$new->[3]}, exists $data{$element}->{3} ? [ { $i => [ $data{$element}->{3} ] } ] : [ $i ];

                push @{$new->[4]}, $data{$element}->{4};
                push @{$new->[5]}, $data{$element}->{5};

                foreach my $key (keys %{$data{$element}->{6}}) {
                    push @{$new->[6]->{$key}}, @{$data{$element}->{6}->{$key}};
                }

                push @expansions, [ $types , $new ];
            }
        }
    }

    return @expansions;
}

1;
__END__

=head1 NAME

DateTime::Format::Natural::Expand - Expand grammar at runtime

=head1 SYNOPSIS

 Please see the DateTime::Format::Natural documentation.

=head1 DESCRIPTION

C<DateTime::Format::Natural::Expand> dynamically expands the grammar
at runtime in order to allow for additional time to be parsed.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=head1 AUTHOR

Steven Schubiger <schubiger@cpan.org>

=head1 LICENSE

This program is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/>

=cut
