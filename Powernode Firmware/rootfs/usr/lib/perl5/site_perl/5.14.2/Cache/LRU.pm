package Cache::LRU;

use strict;
use warnings;

use 5.008_001;

use Scalar::Util qw();

our $VERSION = '0.03';

sub GC_FACTOR () { 10 }

sub new {
    my ($klass, %args) = @_;
    return bless {
        size    => 1024,
        %args,
        _entries => {}, # $key => $weak_valueref
        _fifo    => [], # fifo queue of [ $key, $valueref ]
    }, $klass;
}

sub set {
    my ($self, $key, $value) = @_;

    my $entries = $self->{_entries};

    if (my $old_value_ref = $entries->{$key}) {
        $$old_value_ref = undef;
    }

    # register
    my $value_ref = \$value;
    Scalar::Util::weaken($entries->{$key} = $value_ref);
    $self->_update_fifo($key, $value_ref);

    # expire the oldest entry if full
    while (scalar(keys %$entries) > $self->{size}) {
        my $exp_key = shift(@{$self->{_fifo}})->[0];
        delete $entries->{$exp_key}
            unless $entries->{$exp_key};
    }

    $value;
}

sub remove {
    my ($self, $key) = @_;
    my $value_ref = delete $self->{_entries}->{$key};
    return undef unless $value_ref;
    my $value = $$value_ref;
    $$value_ref = undef;
    $value;
}

sub get {
    my ($self, $key) = @_;

    my $value_ref = $self->{_entries}->{$key};
    return undef unless $value_ref;

    $self->_update_fifo($key, $value_ref);
    $$value_ref;
}

sub _update_fifo {
    # precondition: $self->{_entries} should contain given key
    my ($self, $key, $value_ref) = @_;
    my $fifo = $self->{_fifo};

    push @$fifo, [ $key, $value_ref ];
    if (@$fifo >= $self->{size} * GC_FACTOR) {
        my $entries = $self->{_entries};
        my @new_fifo;
        my %need = map { $_ => 1 } keys %$entries;
        while (%need) {
            my $fifo_entry = pop @$fifo;
            unshift @new_fifo, $fifo_entry
                if delete $need{$fifo_entry->[0]};
        }
        $self->{_fifo} = \@new_fifo;
    }
}

1;
__END__

=head1 NAME

Cache::LRU - a simple, fast implementation of LRU cache in pure perl

=head1 SYNOPSIS

    use Cache::LRU;

    my $cache = Cache::LRU->new(
        size => $max_num_of_entries,
    );

    $cache->set($key => $value);

    $value = $cache->get($key);

    $removed_value = $cache->remove($key);

=head1 DESCRIPTION

Cache::LRU is a simple, fast implementation of an in-memory LRU cache in pure perl.

=head1 FUNCTIONS

=head2 Cache::LRU->new(size => $max_num_of_entries)

Creates a new cache object.  Takes a hash as the only argument.  The only parameter currently recognized is the C<size> parameter that specifies the maximum number of entries to be stored within the cache object.

=head2 $cache->get($key)

Returns the cached object if exists, or undef otherwise.

=head2 $cache->set($key => $value)

Stores the given key-value pair.

=head2 $cache->remove($key)

Removes data associated to the given key and returns the old value, if any.

=head1 AUTHOR

Kazuho Oku

=head1 SEE ALSO

L<Cache>

L<Cache::Ref>

L<Tie::Cache::LRU>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See <http://www.perl.com/perl/misc/Artistic.html>

=cut
