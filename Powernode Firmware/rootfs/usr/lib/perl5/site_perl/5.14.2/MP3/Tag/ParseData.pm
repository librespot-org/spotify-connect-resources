package MP3::Tag::ParseData;

use strict;
use vars qw /$VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::ParseData - Module for parsing arbitrary data associated with music files.

=head1 SYNOPSIS

   # parses the file name according to one of the patterns:
   $mp3->config('parse_data', ['i', '%f', '%t - %n - %a.%e', '%t - %y.%e']);
   $title = $mp3->title;

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::ParseData is designed to be called from the MP3::Tag module.

Each option of configuration item C<parse_data> should be of the form
C<[$flag, $string, $pattern1, ...]>.  For each of the option, patterns of
the option are matched agains the $string of the option, until one of them
succeeds.  The information obtained from later options takes precedence over
the information obtained from earlier ones.

The meaning of the patterns is the same as for parse() or parse_rex() methods
of C<MP3::Tag>.  Since the default for C<parse_data> is empty, by default this
handler has no effect.

$flag is split into 1-character-long flags (unknown flags are ignored):

=over

=item C<i>

the string-to-parse is interpolated first;

=item C<f>

the string-to-parse is interpreted as the name of the file to read;

=item C<F>

added to C<f>, makes it non-fatal if the file does not exist;

=item C<B>

the file should be read in C<binary> mode;

=item C<n>

the string-to-parse is interpreted as collection of lines, one per track;

=item C<l>

the string-to-parse is interpreted as collection of lines, and the first
matched is chosen;

=item C<I>

the resulting string is interpolated before parsing.

=item C<b>

Do not strip the leading and trailing blanks.  (With output to file,
the output is performed in binary mode too.)

=item C<R>

the patterns are considered as regular expressions.

=item C<m>

one of the patterns must match.

=item C<o>, C<O>, C<D>

With C<o> or C<O> interpret the pattern as a name of file to output
parse-data to.  With C<O> the name of output file is interpolated.
When C<D> is present, intermediate directories are created.

=item C<z>

Do not ignore a field even if the result is a 0-length string.

=back

Unless C<b> option is given, the resulting values have starting and
trailing whitespace trimmed.  (Actually, split()ing into lines is done
using the configuration item C<parse_split>; it defaults to C<"\n">.)

If the configuration item C<parse_data> has multiple options, the $strings
which are interpolated will use information set by preceding options;
similarly, any interolated option may use information obtained by other
handlers - even if these handers are later in the pecking order than
C<MP3::Tag::ParseData> (which by default is the first handler).  For
example, with

  ['i', '%t' => '%t (%y)'], ['i', '%t' => '%t - %c']

and a local CDDB file which identifies title to C<'Merry old - another
interpretation (1905)'>, the first field will interpolate C<'%t'> into this
title, then will split it into the year and the rest.  The second field will
split the rest into a title-proper and comment.

Note that one can use fields of the form

  ['mz', 'This is a forced title' => '%t']

to force particular values for parts of the MP3 tag.

The usual methods C<artist>, C<title>, C<album>, C<comment>, C<year>, C<track>,
C<year> can be used to access the results of the parse.

It is possible to set individual id3v2 frames; use %{TIT1} or
some such.  Setting to an empty string deletes the frame if config
parameter C<id3v2_frame_empty_ok> is false (the default value).
Setting ID3v2 frames uses the same translation rules as
select_id3v2_frame_by_descr().

=head2 SEE ALSO

The flags C<i f F B l m I b> are identical to flags of the method
interpolate_with_flags() of MP3::Tag (see L<MP3::Tag/"interpolate_with_flags">).
Essentially, the other flags (C<R m o O D z>) are applied to the result of
calling the latter method.

=cut


# Constructor

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    $filename = $filename->filename if ref $filename;
    bless {filename => $filename, parent => $parent}, $class;
}

# Destructor

sub DESTROY {}

sub parse_one {
    my ($self, $in) = @_;

    my @patterns = @$in;		# Apply shift to a copy, not original...
    my $flags = shift @patterns;
    my $data  = shift @patterns;

    my @data = $self->{parent}->interpolate_with_flags($data, $flags);
    my $res;
    my @opatterns = @patterns;

    if ($flags =~ /[oO]/) {
	@patterns = map $self->{parent}->interpolate($_), @patterns
	    if $flags =~ /O/;
	return unless length $data[0] or $flags =~ /z/;
	for my $file (@patterns) {
	    if ($flags =~ /D/ and $file =~ m,(.*)[/\\],s) {
		require File::Path;
		File::Path::mkpath($1);
	    }
	    open OUT, "> $file" or die "open(`$file') for write: $!";
	    if ($flags =~ /b/) {
	      binmode OUT;
	    } else {
	      my $e;
	      if ($e = $self->get_config('encode_encoding_files') and $e->[0]) {
		eval "binmode OUT, ':encoding($e->[0])'"; # old binmode won't compile...
	      }
	    }
	    local ($/, $,) = ('', '');
	    print OUT $data[0];
	    close OUT or die "close(`$file') for write: $!";
	}
	return;
    }
    if ($flags =~ /R/) {
	@patterns = map $self->{parent}->parse_rex_prepare($_), @patterns;
    } else {
	@patterns = map $self->{parent}->parse_prepare($_), @patterns;
    }
    for $data (@data) {
	my $pattern;
	for $pattern (@patterns) {
	    last if $res = $self->{parent}->parse_rex_match($pattern, $data);
	}
	last if $res;
    }
    {   local $" = "' `";
	die "Pattern(s) `@opatterns' did not succeed vs `@data'"
	    if $flags =~ /m/ and not $res;
    }
    my $k;
    for $k (keys %$res) {
	unless ($flags =~ /b/) {
	  $res->{$k} =~ s/^\s+//;
	  $res->{$k} =~ s/\s+$//;
	}
	delete $res->{$k} unless length $res->{$k} or $flags =~ /z/;
    }
    return unless $res and keys %$res;
    return $res;
}

# XXX Two decisions: which entries can access results of which ones,
# and which entries overwrite which ones; the user can reverse one of them
# by sorting config('parse_data') in the opposite order; but not both.
# Only practice can show whether our choice is correct...   How to customize?

sub parse {	# Later recipies can access results of earlier ones.
    my ($self,$what) = @_;

    return $self->{parsed}->{$what}	# Recalculate during recursive calls
	if not $self->{parsing} and exists $self->{parsed}; # Do not recalc after finish

    my $data = $self->get_config('parse_data');
    return unless $data and @$data;
    my $parsing = $self->{parsing};
    local $self->{parsing};

    my (%res, $d, $c);
    for $d (@$data) {
	$c++;
	$self->{parsing} = $c;
	# Protect against recursion: later $d can access results of earlier ones
	last if $parsing and $parsing <= $c;
	my $res = $self->parse_one($d);
	# warn "Failure: [@$d]\n" unless $res;
	# Set user-scratch space data immediately
	for my $k (keys %$res) {
	  if ($k eq 'year') {	# Do nothing
	  } elsif ($k =~ /^U(\d{1,2})$/) {
	    $self->{parent}->set_user($1, delete $res->{$k})
	  } elsif (0 and $k =~ /^\w{4}(\d{2,})?$/) {
	    if (length $res->{$k}
		or $self->get_config('id3v2_frame_empty_ok')->[0]) {
	      $self->{parent}->set_id3v2_frame($k, delete $res->{$k})
	    } else {
	      delete $res->{$k};
	      $self->{parent}->set_id3v2_frame($k);	# delete
	    }
	  } elsif ($k =~ /^\w{4}(\d{2,}|(?:\(([^()]*(?:\([^()]+\)[^()]*)*)\))?(?:\[(\\.|[^]\\]*)\])?)$/) {
	    my $r = delete $res->{$k};
	    $r = undef unless length $r or $self->get_config('id3v2_frame_empty_ok')->[0];
	    if (defined $r or $self->{parent}->_get_tag('ID3v2')) {
	      $self->{parent}->select_id3v2_frame_by_descr($k, $r);
	    }
	  }
	}
	# later ones overwrite earlier
	%res = (%res, %$res) if $res;
    }
    $self->{parsed} = \%res;
    # return unless keys %res;
    return $self->{parsed}->{$what};
}

for my $elt ( qw( title track artist album comment year genre ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    my $self = shift;
    $self->parse($elt, @_);
  }
}

1;
