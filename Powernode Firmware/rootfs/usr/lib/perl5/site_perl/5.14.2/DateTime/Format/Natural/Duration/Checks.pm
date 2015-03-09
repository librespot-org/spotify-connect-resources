package DateTime::Format::Natural::Duration::Checks;

use strict;
use warnings;
use boolean qw(true false);

our $VERSION = '0.01';

sub for
{
    my ($duration, $date_strings, $present) = @_;

    if (@$date_strings == 1
      && $date_strings->[0] =~ $duration->{for}{regex}
    ) {
        $$present = $duration->{for}{present};
        return true;
    }
    else {
        return false;
    }
}

sub first_to_last
{
    my ($duration, $date_strings, $extract) = @_;

    my %regexes = %{$duration->{first_to_last}{regexes}};

    if (@$date_strings == 2
      && $date_strings->[0] =~ $regexes{first}
      && $date_strings->[1] =~ $regexes{last}
    ) {
        $$extract = $regexes{extract};
        return true;
    }
    else {
        return false;
    }
}

sub from_count_to_count
{
    my ($duration, $date_strings, $extract, $adjust) = @_;

    return false unless @$date_strings == 2;

    my $data = $duration->{from_count_to_count};

    my %categories;
    foreach my $ident (@{$data->{order}}) {
        my $category = $data->{categories}{$ident};
        push @{$categories{$category}}, $ident;
    }
    my $from_matches = sub
    {
        my ($entry) = @_;
        foreach my $ident (@{$data->{order}}) {
            if ($date_strings->[0] =~ $data->{regexes}{$ident}) {
                $$entry = $ident;
                return true;
            }
        }
        return false;
    };
    my $to_relative_category = sub
    {
        my ($entry) = @_;
        my $category = $data->{categories}{$entry};
        foreach my $ident (@{$categories{$category}}) {
            if ($date_strings->[1] =~ /^$data->{regexes}{$ident}$/) {
                return true;
            }
        }
        return false;
    };

    my $entry;
    return false unless $from_matches->(\$entry) && $to_relative_category->($entry);

    my $regex = $data->{regexes}{$entry};

    if ($date_strings->[0] =~ /^.+? \s+ $regex$/x) {
        $$extract = qr/^(.+?) \s+ $regex$/x;
        $$adjust  = sub
        {
            my ($date_strings, $complete) = @_;
            $date_strings->[1] = "$complete $date_strings->[1]";
        };
        return true;
    }
    elsif ($date_strings->[0] =~ /^$regex \s+ .+$/x) {
        $$extract = qr/^$regex \s+ (.+)$/x;
        $$adjust  = sub
        {
            my ($date_strings, $complete) = @_;
            $date_strings->[1] .= " $complete";
        };
        return true;
    }
    else {
        return false;
    }
}

1;
