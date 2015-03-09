package MP3::Tag::CDDB_File;

use strict;
use File::Basename;
use File::Spec;
use vars qw /$VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::CDDB_File - Module for parsing CDDB files.

=head1 SYNOPSIS

  my $db = MP3::Tag::CDDB_File->new($filename, $track);	# Name of audio file
  my $db = MP3::Tag::CDDB_File->new_from($record, $track); # Contents of CDDB 

  ($title, $artist, $album, $year, $comment, $track) = $db->parse();

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::CDDB_File is designed to be called from the MP3::Tag module.

It parses the content of CDDB file.

The file is found in the same directory as audio file; the list of possible
file names is taken from the field C<cddb_files> if set by MP3::Tag config()
method.

=over 4

=cut


# Constructor

sub new_from {
    my ($class, $data, $track) = @_;
    bless {data => [split /\n/, $data], track => $track}, $class;
}

sub new_setdir {
    my $class = shift;
    my $filename = shift;
    $filename = $filename->filename if ref $filename;
    $filename = dirname($filename);
    return bless {dir => $filename}, $class;	# bless to enable get_config()
}

sub new_fromdir {
    my $class = shift;
    my $h = shift;
    my $dir = $h->{dir};
    my ($found, $e);
    my $l = $h->get_config('cddb_files');
    for my $file (@$l) {
	my $f = File::Spec->catdir($dir, $file);
	$found = $f, last if -r $f;
    }
    return unless $found;
    local *F;
    open F, "< $found" or die "Can't open `$found': $!";
    if ($e = $h->get_config('decode_encoding_cddb_file') and $e->[0]) {
      eval "binmode F, ':encoding($e->[0])'"; # old binmode won't compile...
    }
    my @data = <F>;
    close F or die "Error closing `$found': $!";
    bless {filename => $found, data => \@data, track => shift,
	   parent => $h->{parent}}, $class;
}

sub new {
    my $class = shift;
    my $h = $class->new_setdir(@_);
    $class->new_fromdir($h);
}

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    my $h = $class->new_setdir($filename);
    $h->{parent} = $parent;
    $class->new_fromdir($h);
}

# Destructor

sub DESTROY {}

=item parse()

  ($title, $artist, $album, $year, $comment, $track) =
     $db->parse($what);

parse_filename() extracts information about artist, title, track number,
album and year from the CDDB record.  $what is optional; it maybe title,
track, artist, album, year, genre or comment. If $what is defined parse() will return
only this element.

Additionally, $what can take values C<artist_collection> (returns the value of
artist in the disk-info field DTITLE, but only if author is specified in the
track-info field TTITLE), C<title_track> (returns the title specifically from
track-info field - the C<track> may fall back to the info from disk-info
field), C<comment_collection> (processed EXTD comment), C<comment_track>
(processed EXTT comment).

The returned year and genre is taken from DYEAR, DGENRE, EXTT, EXTD fields;
recognized prefixes in the two last fields are YEAR, ID3Y, ID3G.
The declarations of this form are stripped from the returned comment.

An alternative
syntax "Recorded"/"Recorded on"/"Recorded in"/ is also supported; the format
of the date recognized by ID3v2::year(), or just a date field without a prefix.

=cut

sub return_parsed {
    my ($self,$what) = @_;
    if (defined $what) {
	return $self->{parsed}{a_in_title}  if $what =~/^artist_collection/i;
	return $self->{parsed}{t_in_track}  if $what =~/^title_track/i;
	return $self->{parsed}{extt}  if $what =~/^comment_track/i;
	return $self->{parsed}{extd}  if $what =~/^comment_collection/i;
	return $self->{parsed}{DISCID}  if $what =~/^cddb_id/i;
	return $self->{parsed}{album}  if $what =~/^al/i;
	return $self->{parsed}{artist} if $what =~/^a/i;
	return $self->{parsed}{track}  if $what =~/^tr/i;
	return $self->{parsed}{year}   if $what =~/^y/i;
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
    return if $self->{fields};
    for my $l (@{$self->{data}}) {
	next unless $l =~ /^\s*(\w+)\s*=(\s*(.*))/;
	my $app = $2;
	$self->{fields}{$1} = "", $app = $3 unless exists $self->{fields}{$1};
	$self->{fields}{$1} .= $app;
	$self->{last} = $1 if $1 =~ /\d+$/;
    }    
    s/\\([nt\\])/$r{$1}/g for values %{$self->{fields}};
}

sub parse {
    my ($self,$what) = @_;
    return $self->return_parsed($what)	if exists $self->{parsed};
    $self->parse_lines;
    my %parsed;
    my ($t1, $c1, $t2, $c2) = map $self->{fields}{$_}, qw(DTITLE EXTD);
    my $track = $self->track;
    if ($track) {
	my $t = $track - 1;
	($t2, $c2) = map $self->{fields}{$_}, "TTITLE$t", "EXTT$t";
    }
    my ($a, $t, $aa, $tt, $a_in_title, $t_in_track);
    ($a, $t) = split /\s+\/\s+/, $t1, 2 if defined $t1;
    ($a, $t) = ($t, $a) unless defined $t;
    ($aa, $tt) = split /\s+\/\s+/, $t2, 2 if defined $t2;
    ($aa, $tt) = ($tt, $aa) unless defined $tt;
    undef $a if defined $a and $a =~ 
	/^\s*(<<\s*)?(Various Artists|compilation disc)\s*(>>\s*)?$/i;
    undef $aa if defined $aa and $aa =~ 
	/^\s*(<<\s*)?(Various Artists|compilation disc)\s*(>>\s*)?$/i;
    $a_in_title = $a if defined $a and length $a and defined $aa and length $aa;
    $aa = $a unless defined $aa and length $aa;
    $t_in_track = $tt;
    $tt = $t unless defined $tt and length $tt;

    my ($y, $cat) = ($self->{fields}{DYEAR}, $self->{fields}{DGENRE});
    for my $f ($c2, $c1) {
      if (defined $f and length $f) { # Process old style declarations
	while ($f =~ s/^\s*((YEAR|ID3Y)|ID3G)\b:?\s*(\d+)\b\s*(([;.,]|\s-\s)\s*)?//i
	       || $f =~ s/(?:\s*(?:[;.,]|\s-\s))?\s*\b((YEAR|ID3Y)|ID3G)\b:?\s*(\d+)\s*([;.,]\s*)?$//i) {
	    $y = $3 if $2 and not $y;
	    $cat = $3 if not $2 and not $cat;
	}
	if ($f =~ s{
		     ((^|[;,.]|\s+-\s) # 1,2
		      \s*
		      (Recorded (\s+[io]n)? \s* (:\s*)? )? # 3, 4, 5
		      (\d{4}([-,][-\d\/,]+)?) # 6, 7
		      \b \s* (?: [.;] \s* )? 
		      ((?:[;.,]|\s-\s|$)\s*)) # 8
		   }
	           {
		    ((($self->{parent}->get_config('comment_remove_date'))->[0]
		       and not ($2 and $8))
		      ? '' : $1) . ($2 && $8 ? $8 : '')
		   }xeim and not ($2 and $8)) {
	    # Overwrite the disk year for longer forms
	    $y = $6 if $3 or $7 or not $y or $c2 and $f eq $c2;
	}
	$f =~ s/^\s+//;
	$f =~ s/\s+$//;
	undef $f unless length $f;
      }
    }
    my ($cc1, $cc2) = ($c1, $c2);
    if (defined $c2 and length $c2) { # Merge unless one is truncation of another
	if ( defined $c1 and length $c1
	     and $c1 ne substr $c2, 0, length $c1
	     and $c1 ne substr $c2, -length $c1 ) {
	    $c2 =~ s/\s*[.,:;]$//;
	    my $sep = (("$c1$c2" =~ /\n/) ? "\n" : '; ');
	    $c1 = "$c2$sep$c1";
	} else {
	    $c1 = $c2;
	}
    }
    if (defined $cat and $cat =~ /^\d+$/) {
	require MP3::Tag::ID3v1;
	$cat = $MP3::Tag::ID3v1::winamp_genres[$cat] if $cat < scalar @MP3::Tag::ID3v1::winamp_genres;
    }

    @parsed{ qw( title artist album year comment track genre
		 a_in_title t_in_track extt extd) } =
	($tt, $aa, $t, $y, $c1, $track, $cat, $a_in_title, $t_in_track, $cc2, $cc1);
    $parsed{DISCID} = $self->{fields}{DISCID};
    $self->{parsed} = \%parsed;
    $self->return_parsed($what);
}


=pod

=item title()

 $title = $db->title();

Returns the title, obtained from the C<'Tracktitle'> entry of the file.

=cut

*song = \&title;

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

Returns the C<'Trackcomment'> entry of the file.  (Often not present.)

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

for my $elt ( qw( cddb_id ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    return shift->parse($elt);
  }
}

1;
