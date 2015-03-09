package MP3::Tag::Cue;

use strict;
use File::Basename;
#use File::Spec;
use vars qw /$VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::Cue - Module for parsing F<.cue> files.

=head1 SYNOPSIS

  my $db = MP3::Tag::Cue->new($filename, $track);	# Name of audio file
  my $db = MP3::Tag::Cue->new_from($record, $track); # Contents of .cue file

  ($title, $artist, $album, $year, $comment, $track) = $db->parse();

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::Cue is designed to be called from the MP3::Tag module.

It parses the content of a F<.cue> file.

The F<.cue> file is looked for in the same directory as audio file; one of the
following conditions must be satisfied:

=over 4

=item *

The "audio" file is specified is actually a F<.cue> file;

=item *

There is exactly one F<.cue> file in the directory of audio file;

=item *

There is exactly one F<.cue> file in the directory of audio file
with basename which is a beginning of the name of audio file.

=item *

There is exactly one F<.cue> file in the directory of audio file
with basename which matches (case-insensitive) a beginning of the
name of audio file.

=back

If no F<.cue> file is found in the directory of audio file, the same process
is repeated once one directory uplevel, with the name of the file's directory
used instead of the file name.  E.g., with the files like this

   Foo/bar.cue
   Foo/bar/04.wav

audio file F<Foo/bar/04.wav> will be associated with F<Foo/bar.cue>.

=cut


# Constructor

sub new_from {
    my ($class, $data, $track) = @_;
    bless {data => [split /\n/, $data], track => $track}, $class;
}

sub matches($$$) {
  my ($f1, $f, $case) =  (shift, shift, shift);
  substr($f1, -4, 4) = '';
  return $f1 eq substr $f, 0, length $f1 if $case;
  return lc $f1 eq lc substr $f, 0, length $f1;
}

sub find_cue ($$) {
  my ($f, $d, %seen) = (shift, shift);
  require File::Glob;			# "usual" glob() fails on spaces...
  my @cue = (File::Glob::bsd_glob("$d/*.cue"), File::Glob::bsd_glob('$d/*.CUE'));
  @seen{@cue} = (1) x @cue;		    # remove duplicates:
  @cue = keys %seen;
  my $c = @cue;
  @cue = grep matches($_, $f, 0), @cue if @cue > 1;
  @cue = grep matches($_, $f, 1), @cue if @cue > 1;
  ($c, @cue)
}

sub new_with_parent {
    my ($class, $f, $p, $e, %seen, @cue) = (shift, shift, shift);
    $f = $f->filename if ref $f;
    $f = MP3::Tag->rel2abs($f);
    if ($f =~ /\.cue$/i and -f $f) {
      @cue = $f;
    } else {
      my $d = dirname($f);
      (my $c, @cue) = find_cue($f, $d);
      unless ($c) {
	my $d1 = dirname($d);
        (my $c, @cue) = find_cue($d, $d1);
      }
    }
    return unless @cue == 1;
    local *F;
    open F, "< $cue[0]" or die "Can't open `$cue[0]': $!";
    if ($e = ($p or 'MP3::Tag')->get_config1('decode_encoding_cue_file')) {
      eval "binmode F, ':encoding($e->[0])'"; # old binmode won't compile...
    }
    my @data = <F>;
    close F or die "Error closing `$cue[0]': $!";
    bless {filename => $cue[0], data => \@data, track => shift,
	   parent => $p}, $class;
}

sub new {
    my ($class, $f) = (shift, shift);
    $class->new_with_parent($f, undef, @_);
}

# Destructor

sub DESTROY {}

=over 4

=item parse()

  ($title, $artist, $album, $year, $comment, $track) =
     $db->parse($what);

parse_filename() extracts information about artist, title, track number,
album and year from the F<.cue> file.  $what is optional; it maybe title,
track, artist, album, year, genre or comment. If $what is defined parse() will return
only this element.

Additionally, $what can take values C<artist_collection> (returns the value of
artist in the whole-disk-info field C<PERFORMER>, C<songwriter>.

=cut

sub return_parsed {
    my ($self,$what) = @_;
    if (defined $what) {
	return $self->{parsed}{collection_performer}  if $what =~/^artist_collection/i;
	return $self->{parsed}{album}  if $what =~/^al/i;
	return $self->{parsed}{performer} if $what =~/^a/i;
	return $self->{parsed}{songwriter} if $what =~/^songwriter/i;
	return $self->{parsed}{track}  if $what =~/^tr/i;
	return $self->{parsed}{date}   if $what =~/^y/i;
	return $self->{parsed}{comment}if $what =~/^c/i;
	return $self->{parsed}{genre}  if $what =~/^g/i;
	return $self->{parsed}{title};
    }
    
    return $self->{parsed} unless wantarray;
    return map $self->{parsed}{$_} , qw(title artist album year comment track);
}

my %r = ( 'n' => "\n", 't' => "\t", '\\' => "\\"  );

sub parse_lines {
    my ($self) = @_;
#    return if $self->{fields};
    my $track_seen = '';
    my $track = $self->track;
    $track = -1e100 unless $track or length $track;
    for my $l (@{$self->{data}}) {
	# http://digitalx.org/cuesheetsyntax.php
	# http://wiki.hydrogenaudio.org/index.php?title=Cuesheet
	# What about http://cue2toc.sourceforge.net/ ?  Can it deal with .toc of cdrecord?
	# http://www.willwap.co.uk/Programs/vbrfix.php - may inspect gap info???
	next unless $l =~ /^\s*(REM\s+)?
			    (GENRE|DATE|DISCID|COMMENT|PERFORMER|TITLE
			     |ISRC|POSTGAP|PREGAP|SONGWRITER
			     |FILE|INDEX|TRACK|CATALOG|CDTEXTFILE|FLAGS)\s+(.*)/x;
	my $field = lc $2;
	my $val = $3;
	$val =~ s/^\"(.*)\"/$1/;	# Ignore trailing fields after TRACK, FILE
	$track_seen = $1 if $field eq 'track' and $val =~ /^0?(\d+)/;
	next if length $track_seen and $track_seen != $track;

	$self->{fields}{$field} = $val;	# unless exists $self->{fields}{$field};
	next if length $track_seen;
	$self->{fields}{album} = $val if $field eq 'title';
	$self->{fields}{collection_performer} = $val if $field eq 'performer';
    }    
}

sub parse {
    my ($self,$what) = @_;
    return $self->return_parsed($what)	if exists $self->{parsed};
    $self->parse_lines;
    $self->{parsed} = { %{$self->{fields}} };	# Make a copy
    $self->return_parsed($what);
}

=pod

=item title()

 $title = $db->title();

Returns the title, obtained from the C<'Tracktitle'> entry of the file.

=cut

# *song = \&title;

sub title {
    return shift->parse("title");
}

=pod

=item artist()

 $artist = $db->artist();

Returns the artist name, obtained from the C<'Performer'> or
C<'Albumperformer'> entries (the first which is present) of the file.

=cut

sub artist {
    return shift->parse("artist");
}

=pod

=item track()

 $track = $db->track();

Returns the track number, stored during object creation, or queried from
the parent.

=cut

sub track {
  my $self = shift;
  return $self->{track} if defined $self->{track};
  return if $self->{recursive} or not $self->parent_ok;
  local $self->{recursive} = 1;
  return $self->{parent}->track1;
}

=item year()

 $year = $db->year();

Returns the year, obtained from the C<'Year'> entry of the file.  (Often
not present.)

=cut

sub year {
    return shift->parse("year");
}

=pod

=item album()

 $album = $db->album();

Returns the album name, obtained from the C<'Albumtitle'> entry of the file.

=cut

sub album {
    return shift->parse("album");
}

=item comment()

 $comment = $db->comment();

Returns the C<'REM COMMENT'> entry of the file.  (Often not present.)

=cut

sub comment {
    return shift->parse("comment");
}

=item genre()

 $genre = $db->genre($filename);

=cut

sub genre {
    return shift->parse("genre");
}

for my $elt ( qw( artist_collection songwriter ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    return shift->parse($elt);
  }
}

1;
