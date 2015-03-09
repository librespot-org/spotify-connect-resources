package Config::Options;
our $VERSION       = 0.08;
# Copyright (c) 2007 Edward Allen III. All rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.
#

=pod

=head1 NAME

Config::Options - module to provide a configuration hash with option to read from file.

=head1 SYNOPSIS

	use Config::Options;

	my $options = Config::Options->new({ verbose => 1, optionb => 2, mood => "sardonic" });

	# Access option as a hash...
	print "My mode is ", $options->{mood}, "\n";

	# Merge a hash of options...
	$options->options({ optionc => 5, style => "poor"});

	# Merge options from file

	$options->options("optionfile", $ENV{HOME} . "/.myoptions.conf");
	$options->fromfile_perl();


=head1 AUTHOR

Edward Allen, ealleniii _at_ cpan _dot_ org

=head1 DESCRIPTION

The motivation for this module was to provide an option hash with a little bit of brains. It's
pretty simple and used mainly by other modules I have written.

=cut

use strict;
use Data::Dumper;
use Carp;
use Scalar::Util;
use Config;

=pod

=head1 METHODS

=over 4

=item new()

Create new options hash.  Pass it  a hash ref to start with.  Please note that this reference
is copied, not blessed.

	my $options = Config::Options->new({hash_of_startup_options}); 

=cut

sub new {
	my $class = shift;
	if ($Config{useithreads}) {
		require Config::Options::Threaded;
		return Config::Options::Threaded->new(@_);
	}
	else {
		return $class->_new(@_);
	}
}

sub _new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    $self->options(@_);
}

=item clone()

Creates a clone of options object.

	my $newoptions = $options->clone();

=cut

sub clone {
    my $self  = shift;
    my $clone = {%$self};
    bless $clone, ref $self;
    return $clone;
}

=item options()

This is a utility function for accessing options.  If passed a hashref, merges it.
If passed a scalar, returns the value.  If passed two scalars, sets the option. 

	my $optionsb = $options->options;     # Duplicates option file.  Not very usefull.
	$options->options($hashref);          # Same as $options->merge($hashref);
	my $value = $options->options("key")  # Return option value.
	$options->options("key", "value")	  # Set an option.

=cut

sub options {
    my $self   = shift;
    my $option = shift;
    if ( ref $option ) {
        return $self->merge($option);
    }
    elsif ($option) {
        my $value = shift;
        if ( defined $value ) {
			$self->_setoption($option, $value);
            $self->{$option} = $value;
        }
        return $self->{$option};
    }
    return $self;
}


=item merge()

Takes a hashref as argument and merges with current options.

	$options->merge($hashref); 


=cut

sub merge {
    my $self   = shift;
    my $option = shift;
    return unless ( ref $option );
    while ( my ( $k, $v ) = each %{$option} ) {
		$self->_setoption($k, $v);
    }
    return $self;
}

# Safely set an option
sub _setoption {
	my $self = shift;
	my ($key, $value) = @_;
	my $new = $value;
	if (ref $value) {
		$new = $self->_copyref($value);
	}
	$self->{$key} = $new;
	return $value;
}

sub _newhash {
	return {};
}

sub _newarray {
	return [];
}


# Created a shared copy of a (potentially unshared) reference
sub _copyref {
	my $self = shift;
	my $in = shift;
	my $haveseen = shift || [];
	my $depth = shift || 0;
	if (++$depth > 20) {
	   carp "More than 20 deep on nested reference.  Is this a loop?";
	   return $in;
	}
	my $seen = [ @{$haveseen} ];
	foreach (@{$seen}) { if(Scalar::Util::refaddr($in) == $_) { carp "Attempt to create circular reference!"; return $in } }
	push @{$seen}, Scalar::Util::refaddr($in);
	if (Scalar::Util::reftype($in) eq "HASH") {
		my $out = $self->_newhash();
		while (my ($k, $v) = each %{$in}) {
			if (ref $v) {
				$out->{$k} = $self->_copyref($v, $seen, $depth);
			}
			else {
				$out->{$k} = $v;
			}
		}
		return $out;
	}
	elsif (Scalar::Util::reftype($in) eq "ARRAY") {
		my $out = $self->_newarray();
		foreach my $v (@{$in}) {
			if (ref $v) {
				push @{$out}, $self->_copyref($v, $seen, $depth);
			}
			else {
				push @{$out}, $v;
			}
		}
		return $out;
	}
	elsif (ref $in) {
		croak "Attempt to copy unsupported reference type: " . (ref $in);
	}
	else {
		return $in;
	}
}

# If $from and $to are both refs of same type, merge.  Otherwise $to replaces $from.
#
sub _mergerefs {
	my $self = shift;
	my $from = shift;
	my $to = shift;
	my $haveseen = shift || [];
	my $depth = shift || 0;
	if (++$depth > 20) {
	   carp "More than 20 deep on nested reference.  Is this a loop?";
	   return $to;
	}
	if (Scalar::Util::refaddr($from) == Scalar::Util::refaddr($to)) {
	   croak "Do NOT try to merge two identical references!"
	}
	my $seen = [ @{$haveseen} ];
	foreach (@{$seen}) { if(Scalar::Util::refaddr($from) == $_) { carp "Attempt to create circular reference!"; return $to } }
	push @{$seen}, Scalar::Util::refaddr($from), Scalar::Util::refaddr($to);
	return unless ((ref $from) && (ref $to));
	if (Scalar::Util::reftype($from) eq Scalar::Util::reftype($to)) {
		if (Scalar::Util::reftype($from) eq "HASH") {
			while (my ($k, $v) = each %{$from} ) {
				if (exists $to->{$k}) {
					if (defined $v) {
						if (ref $v) {
							$self->_mergerefs($from->{$k}, $to->{$k}, $seen, $depth)
						}
						else {
							$to->{$k} = $v;
						}
					}
				}
				else {
					if (ref $v) {
						$to->{$k} = $self->_copyref($v, $seen, $depth);
					}
					else {
						$to->{$k} = $v;
					}
				}
			}
		}
		elsif (Scalar::Util::reftype($from) eq "ARRAY") {
			foreach my $v (@{$from}) {
				if (ref $v) {
					push @{$to}, $self->_copyref($v, $seen, $depth);
				}
				else {
					push @{$to}, $v;
				}
			}
		}
	}
	else {
		$to = $self->_copyref($from, $seen, $depth);
	}
	return $to;
}


=item deepmerge()

Same as merge, except when a value is a hash or array reference.  For example:

	my $options = Config::Options->new({ moods => [ qw(happy sad angry) ] });
	$options->deepmerge({ moods => [ qw(sardonic twisted) ] });

	print join(" ", @{$options->{moods}}), "\n";

The above outputs:

	happy sad angry sardonic twisted

=cut

sub deepmerge {
    my $self   = shift;
    my $option = shift;
	$self->_mergerefs($option, $self);
}

=pod

=item tofile_perl()

This is used to store options to a file. The file is actually a perl program that 
returns a hash.  By default uses option 'optionfile' as filename, or value passed as argument.

If 'optionfile' is an array, then uses LAST option in array as default. 

	$options->tofile_perl("/path/to/optionfile");

=cut

sub tofile_perl {
    my $self = shift;
    my $filename = shift || $self->options("optionfile");
    my $file;
    if ( ref $filename ) {
        $file = $filename->[-1];
    }
    else {
        $file = $filename;
    }
    local *OUT;
    open( OUT, ">", $file ) or croak "Can't open option file: $file for write: $!";
    my $data = $self->serialize();
    print OUT $data;
    close(OUT) or croak "Error closing file: ${file}: $!";
    return $self;
}

=pod

=item fromfile_perl()

This is used to retreive options from a file.  The optionfile is actually a perl program that 
returns a hash.  By default uses option 'optionfile' as filename if none is passed.

If 'optionfile' is an array, reads all option files in order. 

Non-existant files are ignored.

Please note that values for this are cached.

	$options->fromfile_perl("/path/to/optionfile");

=cut

sub fromfile_perl {
    my $self     = shift;
    my $filename = shift || $self->options("optionfile");
    my @files    = ();
    if ( ref $filename eq "ARRAY" ) {
        push @files, @{$filename};
    }
    else {
	    push @files, $filename;
    }
    my $n = 0;
    foreach my $f ( @files ) {
        if ( -e $f ) {
            if ( ( exists $self->{verbose} ) && ( $self->{verbose} ) ) {
                print STDERR "Loading options from $f\n";
            }
            local *IN;
            my $sub = "";
            open( IN, $f ) or croak "Couldn't open option file $f: $!";
            while (<IN>) {
                $sub .= $_;
            }
            close(IN);
            my $o = $self->deserialize( $sub, "Options File: $f" );
	    $o && $n++;
        }
    }
    return $n;
}

=pod

=item deserialize($data, $source)

Takes a scalar as argument and evals it, then merges option.  If second option is given uses this in error message if the eval fails.

	my $options = $options->deserialize($scalar, $source);

=cut

sub deserialize {
    my $self   = shift;
    my $data   = shift;
    my $source = shift || "Scalar";
    my $o      = eval $data;
    if ($@) { croak "Can't process ${source}: $@" }
    else {
        $self->deepmerge($o);
        return $self;
    }
}

=pod

=item serialize()

Output optons hash as a scalar using Data::Dumper. 

	my $scalar = $options->serialize();

=cut

sub serialize {
    my $self = shift;
    my $d = Data::Dumper->new( [ { %{$self} } ] );
    return $d->Purity(1)->Terse(1)->Deepcopy(1)->Dump;
}

=item del($key)

Removes $key from options.

=cut

sub DESTROY {
}

=back

=head1 BUGS

=over 4

=item Deepmerge does a poor job at recogniaing recursive loops.

For example, $options->deepmerge($options) will really screw things up.  As protection, will only loop 20 deep.

=item fromfile_perl provides tainted data. 

Since it comes from an external file, the data is considered tainted.

=back 

=head1 SEE ALSO

L<Config::General>

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=head1 COPYRIGHT

Copyright (c) 2007 Edward Allen III. Some rights reserved.



=cut

1;
