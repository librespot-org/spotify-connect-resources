package Config::Options::Threaded;

our $VERSION       = 0.05;
# Copyright (c) 2007 Edward Allen III. All rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.
#

=pod

=head1 NAME

Config::Options::Threaded - Threaded version of module to provide a configuration hash with option to read from file.

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
use Carp;
use threads;
use threads::shared;
our @ISA = qw( Config::Options );

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
    my $self  = {};
    bless $self, $class;
	&share($self);
    $self->options(@_);
}

=item clone()

Creates a clone of options object.

	my $newoptions = $options->clone();

=cut

sub clone {
    my $self  = shift;
    my $clone = {};
    bless $clone, ref $self;
	&share($clone);
	$clone->merge($self);
    return $clone;
}

=item options()

This is a utility function for accessing options.  If passed a hashref, merges it.
If passed a scalar, returns the value.  If passed two scalars, sets the option. 

	my $optionsb = $options->options;     # Duplicates option file.  Not very usefull.
	$options->options($hashref);          # Same as $options->merge($hashref);
	my $value = $options->options("key")  # Return option value.
	$options->options("key", "value")	  # Set an option.


=item merge()

Takes a hashref as argument and merges with current options.

	$options->merge($hashref); 


=item deepmerge()

Same as merge, except when a value is a hash or array reference.  For example:

	my $options = Config::Options->new({ moods => [ qw(happy sad angry) ] });
	$options->deepmerge({ moods => [ qw(sardonic twisted) ] });

	print join(" ", @{$options->{moods}}), "\n";

The above outputs:

	happy sad angry sardonic twisted


=item tofile_perl()

This is used to store options to a file. The file is actually a perl program that 
returns a hash.  By default uses option 'optionfile' as filename, or value passed as argument.

If 'optionfile' is an array, then uses LAST option in array as default. 

	$options->tofile_perl("/path/to/optionfile");


=item fromfile_perl()

This is used to retreive options from a file.  The optionfile is actually a perl program that 
returns a hash.  By default uses option 'optionfile' as filename if none is passed.

If 'optionfile' is an array, reads all option files in order. 

Non-existant files are ignored.

Please note that values for this are cached.

	$options->fromfile_perl("/path/to/optionfile");


=item deserialize($data, $source)

Takes a scalar as argument and evals it, then merges option.  If second option is given uses this in error message if the eval fails.

	my $options = $options->deserialize($scalar, $source);


=item serialize()

Output optons hash as a scalar using Data::Dumper. 

	my $scalar = $options->serialize();


=item del($key)

Removes $key from options.


=back

=head1 BUGS

=over 4

=item Deepmerge does not handle nested references well, but it tries.

For example, $options->deepmerge($options) is a mess.

=item fromfile_perl provides tainted data. 

Since it comes from an external file, the data is considered tainted.

=back

=head1 SEE ALSO

L<Config::General>

=head1 COPYRIGHT

Copyright (c) 2007 Edward Allen III. All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.


=cut

sub _setoption {
	my $self = shift;
	my ($key, $value) = @_;
	my $new = $value;
	if (ref $value) {
		$new = $self->_copyref($value);
	}
	lock($self);
	$self->{$key} = $new;
	return $value;
}

sub _newhash {
	my $hash =  {};
	&share($hash);
	return $hash;
}

sub _newarray {
	my $array = [];
	&share($array);
	return $array;
}

sub deepmerge {
    my $self   = shift;
    my $option = shift;
	lock($self);
	$self->_mergerefs($option, $self);
}

sub serialize {
    my $self = shift;
	lock($self);
    my $d = Data::Dumper->new( [ { %{$self} } ] );
    return $d->Purity(1)->Terse(1)->Deepcopy(1)->Dump;
}

sub del {
    my $self = shift;
	lock($self);
	my $key = shift;
	delete $self->{$key};
}


1;
