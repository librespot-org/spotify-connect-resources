package MP3::Tag::File;

use strict;
use Fcntl;
use File::Basename;
use vars qw /$VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::File - Module for reading / writing files

=head1 SYNOPSIS

  my $mp3 = MP3::Tag->new($filename);

  ($title, $artist, $no, $album, $year) = $mp3->parse_filename();

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::File is designed to be called from the MP3::Tag module.

It offers possibilities to read/write data from files via read(), write(),
truncate(), seek(), tell(), open(), close(); one can find the filename via
the filename() method.

=cut


# Constructor

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    return undef unless -f $filename or -c $filename;
    return bless {filename => $filename, parent => $parent}, $class;
}
*new = \&new_with_parent;	# Obsolete handler

# Destructor

sub DESTROY {
    my $self=shift;
    if (exists $self->{FH} and defined $self->{FH}) {
	$self->close;
    }
}

# File subs

sub filename { shift->{filename} }

sub open {
    my $self=shift;
    my $mode= shift;
    if (defined $mode and $mode =~ /w/i) {
	$mode=O_RDWR;    # read/write mode
    } else {
	$mode=O_RDONLY;  # read only mode
    }
    unless (exists $self->{FH}) {
	local *FH;
	if (sysopen (FH, $self->filename, $mode)) {
	    $self->{FH} = *FH;
	    binmode $self->{FH};
	} else {
	    warn "Open `" . $self->filename() . "' failed: $!\n";
	}
    }
    return exists $self->{FH};
}


sub close {
    my $self=shift;
    if (exists $self->{FH}) {
	close $self->{FH};
	delete $self->{FH};
    }
}

sub write {
    my ($self, $data) = @_;
    if (exists $self->{FH}) {
	local $\ = '';
	print {$self->{FH}} $data;
    }
}

sub truncate {
    my ($self, $length) = @_;
    if ($length<0) {
	my @stat = stat $self->{FH};
	$length = $stat[7] + $length;
    }
    if (exists $self->{FH}) {
	truncate $self->{FH}, $length;
    }
}

sub size {
    my ($self) = @_;
    return -s $self->{FH} if exists $self->{FH};
    return -s ($self->filename);
}

sub seek {
    my ($self, $pos, $whence)=@_;
    $self->open unless exists $self->{FH};
    seek $self->{FH}, $pos, $whence;
}

sub tell {
    my ($self, $pos, $whence)=@_;
    return undef unless exists $self->{FH};
    return tell $self->{FH};
}

sub read {
    my ($self, $buf_, $length) = @_;
    $self->open unless exists $self->{FH};
    return read $self->{FH}, $$buf_, $length;
}

sub is_open {
    return exists shift->{FH};
}

# keep the old name
*isOpen = \&is_open;

# read and decode the header of the mp3 part of the file
# the raw content of the header fields is stored, the values
# are not interpreted in any way (e.g. layer==3 means 'Layer I'
# as specified in the mp3 format)
sub get_mp3_frame_header {
    my ($self, $start) = @_;

    $start = 0 unless $start;

    if (exists $self->{mp3header}) {
	return $self->{mp3header};
    }

    $self->seek($start, 0);
    my ($data, $bits)="";
    while (1) {
	my $nextdata;
	$self->read(\$nextdata, 512);
	return unless $nextdata; # no header found
	$data .= $nextdata;
	if ($data =~ /(\xFF[\xE0-\xFF]..)/) {
	    $bits = unpack("B32", $1);
	    last;
	}
	$data = substr $data, -3
    }

    my @fields;
    for (qw/11 2 2 1 4 2 1 1 1 2 2 1 1 2/) {
	push @fields, oct "0b" . substr $bits, 0, $_;
	$bits = substr $bits, $_ if length $bits > $_;
    }

    $self->{mp3header}={};
    for (qw/sync version layer proctection bitrate_id sampling_rate_id padding private
	 channel_mode mode_ext copyright original emphasis/) {
	$self->{mp3header}->{$_}=shift @fields;
    }

    return $self->{mp3header}
}


# use filename to determine information about song/artist/album

=pod

=over 4

=item parse_filename()

  ($title, $artist, $no, $album, $year) = $mp3->parse_filename($what, $filename);

parse_filename() tries to extract information about artist, title,
track number, album and year from the filename.  (For backward
compatibility it may be also called by deprecated name
read_filename().)

This is likely to fail for a lot of filenames, especially the album will
be often wrongly guessed, as the name of the parent directory is taken as
album name.

$what and $filename are optional. $what maybe title, track, artist, album
or year. If $what is defined parse_filename() will return only this element.

If $filename is defined this filename will be used and not the real
filename which was set by L<MP3::Tag> with
C<MP3::Tag-E<gt>new($filename)>.  Otherwise the actual filename is used
(subject to configuration variable C<decode_encoding_filename>).

Following formats will be hopefully recognized:

- album name/artist name - song name.mp3

- album_name/artist_name-song_name.mp3

- album.name/artist.name_song.name.mp3

- album name/(artist name) song name.mp3

- album name/01. artist name - song name.mp3

- album name/artist name - 01 - song.name.mp3

If artist or title end in C<(NUMBER)> with 4-digit NUMBER, it is considered
the year.

=cut

*read_filename = \&parse_filename;

sub return_parsed {
    my ($self,$what) = @_;
    if (defined $what) {
	return $self->{parsed}{album}  if $what =~/^al/i;
	return $self->{parsed}{artist} if $what =~/^a/i;
	return $self->{parsed}{no}     if $what =~/^tr/i;
	return $self->{parsed}{year}   if $what =~/^y/i;
	return $self->{parsed}{title};
    }

    return $self->{parsed} unless wantarray;
    return map $self->{parsed}{$_} , qw(title artist no album year);
}

sub parse_filename {
    my ($self,$what,$filename) = @_;
    unless (defined $filename) {
      $filename = $self->filename;
      my $e;
      if ($e = $self->get_config('decode_encoding_filename') and $e->[0]) {
	require Encode;
	$filename = Encode::decode($e->[0], $filename);
      }
    }
    my $pathandfile = $filename;

    $self->return_parsed($what)	if exists $self->{parsed_filename}
				   and $self->{parsed_filename} eq $filename;

    # prepare pathandfile for easier use
    my $ext_rex = $self->get_config('extension')->[0];
    $pathandfile =~ s/$ext_rex//;		# remove extension
    $pathandfile =~ s/ +/ /g; # replace several spaces by one space

    # Keep two last components of the file name
    my ($file, $path) = fileparse($pathandfile, "");
    ($path) = fileparse($path, "");
    my $orig_file = $file;

    # check which chars are used for seperating words
    #   assumption: spaces between words

    unless ($file =~/ /) {
	# no spaces used, find word seperator
	my $Ndot = $file =~ tr/././;
	my $Nunderscore = $file =~ tr/_/_/;
	my $Ndash = $file =~ tr/-/-/;
	if (($Ndot>$Nunderscore) && ($Ndot>1)) {
	    $file =~ s/\./ /g;
	}
	elsif ($Nunderscore > 1) {
	    $file =~ s/_/ /g;
	}
	elsif ($Ndash>2) {
	    $file =~ s/-/ /g;
	}
    }

    # check wich chars are used for seperating parts
    #   assumption: " - " is used

    my $partsep = " - ";

    unless ($file =~ / - /) {
	if ($file =~ /-/) {
	    $partsep = "-";
	} elsif ($file =~ /^\(.*\)/) {
	    # replace brackets by -
	    $file =~ s/^\((.*?)\)/$1 - /;
	    $file =~ s/ +/ /;
	    $partsep = " - ";
	} elsif ($file =~ /_/) {
	    $partsep = "_";
	} else {
	    $partsep = "DoesNotExist";
	}
    }

    # get parts of name
    my ($title, $artist, $no, $album, $year)=("","","","","");

    # try to find a track-number in front of filename
    if ($file =~ /^ *(\d+)[\W_]/) {
	$no=$1;                 # store number
	$file =~ s/^ *\d+//; # and delete it
	$file =~ s/^$partsep// || $file =~ s/^.//;
	$file =~ s/^ +//;
    }

    $file =~ s/_+/ /g unless $partsep =~ /_/; #remove underscore unless they are needed for part seperation
    my @parts = split /$partsep/, $file;
    if (@parts == 1) {
	$title=$parts[0];
	$no = $file if $title and $title =~ /^\d{1,2}$/;
    } elsif (@parts == 2) {
	if ($parts[0] =~ /^\d{1,2}$/) {
	  $no = $parts[0];
	  $title = $file;
	} elsif ($parts[1] =~ /^\d{1,2}$/) {
	  $no = $parts[1];
	  $title = $file;
	} else {
	  $artist=$parts[0];
	  $title=$parts[1];
	}
    } elsif (@parts > 2) {
	my $temp = "";
	$artist = shift @parts;
	foreach (@parts) {
	    if (/^ *(\d+)\.? *$/) {
		$artist.= $partsep . $temp if $temp;
		$temp="";
		$no=$1;
	    } else {
		$temp .= $partsep if $temp;
		$temp .= $_;
	    }
	}
	$title=$temp;
    }

    $title =~ s/ +$//;
    $artist =~ s/ +$//;
    $no =~ s/ +$//;

    # Special-case names like audio12 etc created by some software
    # (cdda2wav, gramofile, etc)
    $no = $+ if not $no and $title =~ /^(\d+)?(?:audio|track|processed)\s*(\d+)?$/i and $+;

    $no =~ s/^0+//;

    if ($path) {
	unless ($artist) {
	    $artist = $path;
	} else {
	    $album = $path;
	}
    }
    # Keep the year in the title/artist (XXXX Should we?)
    $year = $1 if $title =~ /\((\d{4})\)/ or $artist =~ /\((\d{4})\)/;

    $self->{parsed_filename} = $filename;
    $self->{parsed} = { artist=>$artist, song=>$title, no=>$no,
		        album=>$album,  title=>$title, year => $year};
    $self->return_parsed($what);
}


=pod

=item title()

 $title = $mp3->title($filename);

Returns the title, guessed from the filename. See also parse_filename().  (For
backward compatibility, can be called by deprecated name song().)

$filename is optional and will be used instead of the real filename if defined.

=cut

*song = \&title;

sub title {
    my $self = shift;
    return $self->parse_filename("title", @_);
}

=pod

=item artist()

 $artist = $mp3->artist($filename);

Returns the artist name, guessed from the filename. See also parse_filename()

$filename is optional and will be used instead of the real filename if defined.

=cut

sub artist {
    my $self = shift;
    return $self->parse_filename("artist", @_);
}

=pod

=item track()

 $track = $mp3->track($filename);

Returns the track number, guessed from the filename. See also parse_filename()

$filename is optional and will be used instead of the real filename if defined.

=cut

sub track {
    my $self = shift;
    return $self->parse_filename("track", @_);
}

=item year()

 $year = $mp3->year($filename);

Returns the year, guessed from the filename. See also parse_filename()

$filename is optional and will be used instead of the real filename if defined.

=cut

sub year {
    my $self = shift;
    my $y = $self->parse_filename("year", @_);
    return $y if length $y;
    return;
}

=pod

=item album()

 $album = $mp3->album($filename);

Returns the album name, guessed from the filename. See also parse_filename()
The album name is guessed from the parent directory, so it is very likely to fail.

$filename is optional and will be used instead of the real filename if defined.

=cut

sub album {
    my $self = shift;
    return $self->parse_filename("album", @_);
}

=item comment()

 $comment = $mp3->comment($filename);	# Always undef

=cut

sub comment {}

=item genre()

 $genre = $mp3->genre($filename);	# Always undef

=cut

sub genre {}

1;
