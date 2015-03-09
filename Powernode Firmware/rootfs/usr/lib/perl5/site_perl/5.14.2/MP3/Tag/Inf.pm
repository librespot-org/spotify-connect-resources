package MP3::Tag::Inf;

use strict;
use vars qw /$VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::Inf - Module for parsing F<.inf> files associated with music tracks.

=head1 SYNOPSIS

  my $mp3inf = MP3::Tag::Inf->new($filename);	# Name of MP3 or .INF file
						# or an MP3::Tag::File object

  ($title, $artist, $album, $year, $comment, $track) = $mp3inf->parse();

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::Inf is designed to be called from the MP3::Tag module.

It parses the content of F<.inf> file (created, e.g., by cdda2wav).

=over 4

=cut


# Constructor

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    my $self = bless {parent => $parent}, $class;

    $filename = $filename->filename if ref $filename;
    my $ext_rex = $self->get_config('extension')->[0];
    $filename =~ s/($ext_rex)|$/.inf/;		# replace extension
    return unless -f $filename;
    $self->{filename} = $filename;
    $self;
}

# Destructor

sub DESTROY {}

=item parse()

  ($title, $artist, $album, $year, $comment, $track) =
     $mp3inf->parse($what);

parse_filename() extracts information about artist, title, track number,
album and year from the F<.inf> file.  $what is optional; it maybe title,
track, artist, album, year or comment. If $what is defined parse() will return
only this element.

As a side effect of this call, $mp3inf->{info} is set to the hash reference
with the content of particular elements of the F<.inf> file.  Typically present
are the following fields:

  CDINDEX_DISCID
  CDDB_DISCID
  MCN
  ISRC
  Albumperformer
  Performer
  Albumtitle
  Tracktitle
  Tracknumber
  Trackstart
  Tracklength
  Pre-emphasis
  Channels
  Copy_permitted
  Endianess
  Index

The following fields are also recognized:

  Year
  Trackcomment

=cut

sub return_parsed {
    my ($self,$what) = @_;
    if (defined $what) {
	return $self->{parsed}{album}  if $what =~/^al/i;
	return $self->{parsed}{artist} if $what =~/^a/i;
	return $self->{parsed}{track}  if $what =~/^tr/i;
	return $self->{parsed}{year}   if $what =~/^y/i;
	return $self->{parsed}{genre}  if $what =~/^g/i;
	if ($what =~/^cddb_id/i) {
	  my $o = $self->{parsed}{Cddb_discid};
	  $o =~ s/^0x//i if $o;
	  return $o;
	}
	return $self->{parsed}{Cdindex_discid}  if $what =~/^cdindex_id/i;
	return $self->{parsed}{comment}if $what =~/^c/i;
	return $self->{parsed}{title};
    }

    return $self->{parsed} unless wantarray;
    return map $self->{parsed}{$_} , qw(title artist album year comment track);
}

sub parse {
    my ($self,$what) = @_;

    $self->return_parsed($what)	if exists $self->{parsed};
    local *IN;
    open IN, "< $self->{filename}" or die "Error opening `$self->{filename}': $!";
    my $e;
    if ($e = $self->get_config('decode_encoding_inf') and $e->[0]) {
      eval "binmode IN, ':encoding($e->[0])'"; # old binmode won't compile...
    }
    my ($line, %info);
    for $line (<IN>) {
	$self->{info}{ucfirst lc $1} = $2
	    if $line =~ /^(\S+)\s*=\s*['"]?(.*?)['"]?\s*$/;
    }
    close IN or die "Error closing `$self->{filename}': $!";
    my %parsed;
    @parsed{ qw( title artist album year comment track Cddb_discid Cdindex_discid ) } =
	@{ $self->{info} }{ qw( Tracktitle Performer Albumtitle 
				Year Trackcomment Tracknumber
				Cddb_discid Cdindex_discid) };
    $parsed{artist} = $self->{info}{Albumperformer}
	unless defined $parsed{artist};
    $self->{parsed} = \%parsed;
    $self->return_parsed($what);
}

for my $elt ( qw( title track artist album comment year genre cddb_id cdindex_id ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    my $self = shift;
    $self->parse($elt, @_);
  }
}

1;
