package MP3::Tag::ID3v1;

# Copyright (c) 2000-2004 Thomas Geffert.  All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the Artistic License, distributed
# with Perl.

use strict;
use vars qw /@mp3_genres @winamp_genres $AUTOLOAD %ok_length $VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

# allowed fields in ID3v1.1 and max length of this fields (except for track and genre which are coded later)
%ok_length = (title => 30, artist => 30, album => 30, comment => 28, track => 3, genre => 3000, year=>4, genreID=>1); 

=pod

=head1 NAME

MP3::Tag::ID3v1 - Module for reading / writing ID3v1 tags of MP3 audio files

=head1 SYNOPSIS

MP3::Tag::ID3v1 is designed to be called from the MP3::Tag module.

  use MP3::Tag;
  $mp3 = MP3::Tag->new($filename);

  # read an existing tag
  $mp3->get_tags();
  $id3v1 = $mp3->{ID3v1} if exists $mp3->{ID3v1};

  # or create a new tag
  $id3v1 = $mp3->new_tag("ID3v1");

See L<MP3::Tag|according documentation> for information on the above used functions.
  
* Reading the tag

    print "  Title: " .$id3v1->title . "\n";
    print " Artist: " .$id3v1->artist . "\n";
    print "  Album: " .$id3v1->album . "\n";
    print "Comment: " .$id3v1->comment . "\n";
    print "   Year: " .$id3v1->year . "\n";
    print "  Genre: " .$id3v1->genre . "\n";
    print "  Track: " .$id3v1->track . "\n";

    # or at once
    @tagdata = $mp3->all();
    foreach $tag (@tagdata) {
	print $tag;
    }

* Changing / Writing the tag

      $id3v1->comment("This is only a Test Tag");
      $id3v1->title("testing");
      $id3v1->artist("Artest");
      $id3v1->album("Test it");
      $id3v1->year("1965");
      $id3v1->track("5");
      $id3v1->genre("Blues");
      # or at once
      $id3v1->all("song title","artist","album","1900","comment",10,"Ska");
      $id3v1->write_tag();

* Removing the tag from the file

      $id3v1->remove_tag();

=head1 AUTHOR

Thomas Geffert, thg@users.sourceforge.net

=head1 DESCRIPTION

=pod

=over

=item title(), artist(), album(), year(), comment(), track(), genre()

  $artist  = $id3v1->artist;
  $artist  = $id3v1->artist($artist);
  $album   = $id3v1->album;
  $album   = $id3v1->album($album);
  $year    = $id3v1->year;
  $year    = $id3v1->year($year);
  $comment = $id3v1->comment;
  $comment = $id3v1->comment($comment);
  $track   = $id3v1->track;
  $track   = $id3v1->track($track);
  $genre   = $id3v1->genre;
  $genre   = $id3v1->genre($genre);

Use these functions to retrieve the date of these fields,
or to set the data.

$genre can be a string with the name of the genre, or a number
describing the genre.

=cut

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;

  # is it an allowed field
  $attr =~ s/.*:://;
  return unless $attr =~ /[^A-Z]/;
  $attr = 'title' if $attr eq 'song';
  warn "invalid field: ->$attr()" unless $ok_length{$attr};

  if (@_) {
    my $new = shift;
    $new =~ s/ *$//;
    if ($attr eq "genre") {
      if ($new =~ /^\d+$/) {
	$self->{genreID} = $new;
      } else {
	$self->{genreID} = genre2id($new);
      }
      $new = id2genre($self->{genreID})
	if defined $self->{genreID} and $self->{genreID} < @winamp_genres;
    }
    $new = substr  $new, 0, $ok_length{$attr};
    $self->{$attr}=$new;
    $self->{changed} = 1;
  }
  $self->{$attr} =~ s/ +$//;
  return $self->{$attr};
}

=pod

=item all()

  @tagdata = $id3v1->all;
  @tagdata = $id3v1->all($title, $artist, $album, $year, $comment, $track, $genre);

Returns all information of the tag in a list. 
You can use this sub also to set the data of the complete tag.

The order of the data is always title, artist, album, year, comment, track, and  genre.
genre has to be a string with the name of the genre, or a number identifying the genre.

=cut

sub all {
  my $self=shift;
  if ($#_ == 6) {
      my $new;
      for (qw/title artist album year comment track genre/) {
	  $new = shift;
	  $new =~ s/ +$//;
	  $new = substr  $new, 0, $ok_length{$_};
	  $self->{$_}=$new;
      }
      if ($self->{genre} =~ /^\d+$/) {
	  $self->{genreID} = $self->{genre};
      } else {
	  $self->{genreID} = genre2id($self->{genre});
      }
      $self->{genre} = id2genre($self->{genreID})
	if defined $self->{genreID} and $self->{genreID} < @winamp_genres;
      $self->{changed} = 1;
  }
  for (qw/title artist album year comment track genre/) {
      $self->{$_} =~ s/ +$//;
  }
  if (wantarray) {
      return ($self->{title},$self->{artist},$self->{album},
	      $self->{year},$self->{comment}, $self->{track}, $self->{genre});
  }
  return $self->{title};
}

=pod

=item fits_tag()

  warn "data truncated" unless $id3v1->fits_tag($hash);

Check whether the info in ID3v1 tag fits into the format of the file.

=cut

sub fits_tag {
    my ($self, $hash) = (shift, shift);
    my $elt;
    if (defined (my $track = $hash->{track})) {
      $track = $track->[0] if ref $track;
      return unless $track =~ /^\d{0,3}$/ and ($track eq '' or $track < 256);
    }
    my $s = '';
    for $elt (qw(title artist album comment year)) {
	next unless defined (my $data = $hash->{$elt});
	$data = $data->[0] if ref $data;
	return if $data =~ /[^\x00-\xFF]/;
	$s .= $data;
	next if $ok_length{$elt} >= length $data;
	next
	  if $elt eq 'comment' and not $hash->{track} and length $data <= 30;
	return;
    }
    if (defined (my $genre = $hash->{genre})) {
	$genre = $genre->[0] if ref $genre;
        my @g = MP3::Tag::Implemenation::_massage_genres($genre);
	return if @g > 1;
	my $id = MP3::Tag::Implemenation::_massage_genres($genre, 'num');
	return if not defined $id or $id eq '' or $id == 255;
    }
    if ($s =~ /[^\x00-\x7E]/) {
      my $w = ($self->get_config('encode_encoding_v1') || [0])->[0];
      my $r = ($self->get_config('decode_encoding_v1') || [0])->[0];
      $_ = (lc or 'iso-8859-1') for $r, $w;
      # Safe: per-standard and read+write is idempotent:
      return 1 if $r eq $w and $w eq 'iso-8859-1';
      return !(($self->get_config('encoded_v1_fits')||[0])->[0])
	if $w eq 'iso-8859-1';	# read+write not idempotent
      return if $w ne $r
	  and not (($self->get_config('encoded_v1_fits')||[0])->[0]);
    }
    return 1;
}

=item as_bin()

  $str = $id3v1->as_bin();

Returns the ID3v1 tag as a string.

=item write_tag()

  $id3v1->write_tag();

  [old name: writeTag() . The old name is still available, but you should use the new name]

Writes the ID3v1 tag to the file.

=cut

sub as_bin {
    my $self = shift;
    my($t) = ( $self->{track} =~ m[^(\d+)(?:/|$)], 0 );
    my (%f, $f, $e);
    for $f (qw(title artist album comment) ) {
	$f{$f} = $self->{$f};
    }

    if ($e = $self->get_config('encode_encoding_v1') and $e->[0]) {
        my $field;
        require Encode;

        for $field (qw(title artist album comment)) {
          $f{$field} = Encode::encode($e->[0], $f{$field});
        }
    }

    $f{comment} = pack "a28 x C", $f{comment}, $t if $t;
    $self->{genreID}=255 unless $self->{genreID} =~ /^\d+$/;

    return pack("a3a30a30a30a4a30C","TAG",$f{title}, $f{artist},
		$f{album}, $self->{year}, $f{comment}, $self->{genreID});
}

sub write_tag {
    my $self = shift;
    return undef unless exists $self->{title} && exists $self->{changed};
    my $data = $self->as_bin();
    my $mp3obj = $self->{mp3};
    my $mp3tag;
    $mp3obj->close;
    if ($mp3obj->open("write")) {
	$mp3obj->seek(-128,2);
	$mp3obj->read(\$mp3tag, 3);
	if ($mp3tag eq "TAG") {
	    $mp3obj->seek(-125,2); # neccessary for windows
	    $mp3obj->write(substr $data, 3);
	} else {
	    $mp3obj->seek(0,2);
	    $mp3obj->write($data);
	}
    } else {
	warn "Couldn't open file `" . $mp3obj->filename() . "' to write tag";
	return 0;
    }
    return 1;
}

*writeTag = \&write_tag;

=pod

=item remove_tag()

  $id3v1->remove_tag();

Removes the ID3v1 tag from the file.  Returns negative on failure,
FALSE if no tag was found.

(Caveat: only I<one tag> is removed; some - broken - files may have
many chain-loaded one after another; you may need to call remove_tag()
in a loop to handle such beasts.)

[old name: removeTag() . The old name is still available, but you
should use the new name]

=cut

sub remove_tag {
  my $self = shift;
  my $mp3obj = $self->{mp3};
  my $mp3tag;
  $mp3obj->seek(-128,2);
  $mp3obj->read(\$mp3tag, 3);
  if ($mp3tag eq "TAG") {
    $mp3obj->close;
    if ($mp3obj->open("write")) {
      $mp3obj->truncate(-128);
      $self->all("","","","","",0,255);
      $mp3obj->close;
      $self->{changed} = 1;
      return 1;
    }
    return -1;
  }
  return 0;
}

*removeTag = \&remove_tag;

=pod

=item genres()

  @allgenres = $id3v1->genres;
  $genreName = $id3v1->genres($genreID);
  $genreID   = $id3v1->genres($genreName);  

Returns a list of all genres, or the according name or id to
a given id or name.

=cut

sub genres {
    # return an array with all genres, of if a parameter is given, the according genre
    my ($self, $genre) = @_;
    if ( (defined $self) and (not defined $genre) and ($self !~ /MP3::Tag/)) {
	## genres may be called directly via MP3::Tag::ID3v1::genres()
	## and $self is then not used for an id3v1 object
	$genre = $self;
    }

    return \@winamp_genres unless defined $genre;

    if ($genre =~ /^\d+$/) {
	return $winamp_genres[$genre] if $genre<scalar @winamp_genres;
	return undef;
    }

    my ($id, $found)=0;
    foreach (@winamp_genres) {
	if (uc $_ eq uc $genre) {
	    $found = 1;
	    last;
	}
	$id++;
    }
    $id=255 unless $found;
    return $id;
}

=item new()

  $id3v1 = MP3::Tag::ID3v1->new($mp3fileobj[, $create]);

Generally called from MP3::Tag, because a $mp3fileobj is needed.
If $create is true, a new tag is created. Otherwise undef is
returned, if now ID3v1 tag is found in the $mp3obj.

Please use

   $mp3 = MP3::Tag->new($filename);
   $id3v1 = $mp3->new_tag("ID3v1");	# Empty new tag

or

   $mp3 = MP3::Tag->new($filename);
   $mp3->get_tags();
   $id3v1 = $mp3->{ID3v1};		# Existing tag (if present)

instead of using this function directly

=back

=cut

# create a ID3v1 object
sub new {
    my ($class, $fileobj, $create) = @_;
    my $self={mp3=>$fileobj};
    my $buffer;

    if ($create) {
	$self->{new} = 1;
    } else {
	$fileobj->open or return unless $fileobj->is_open;
	$fileobj->seek(-128,2);
	$fileobj->read(\$buffer, 128);
	return undef unless substr ($buffer,0,3) eq "TAG";
    }

    bless $self, $class;
    $self->read_tag($buffer);	# $buffer unused if ->{new}
    return $self;
}

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    return unless my $new = $class->new($filename, undef);
    $new->{parent} = $parent;
    $new;
}

#################
##
## internal subs

# actually read the tag data
sub read_tag {
    my ($self, $buffer) = @_;
    my ($id3v1, $e);

    if ($self->{new}) {
	($self->{title}, $self->{artist}, $self->{album}, $self->{year}, 
	 $self->{comment}, $self->{track}, $self->{genre}, $self->{genreID}) = ("","","","","",'',"",255);
	$self->{changed} = 1;
    } else {
	(undef, $self->{title}, $self->{artist}, $self->{album}, $self->{year}, 
	 $self->{comment}, $id3v1, $self->{track}, $self->{genreID}) = 
	   unpack (($] < 5.6
		    ? "a3 A30 A30 A30 A4 A28 C C C"	# Trailing spaces stripped too
		    : "a3 Z30 Z30 Z30 Z4 Z28 C C C"),
		   $buffer);
	
	if ($id3v1!=0) { # ID3v1 tag found: track is not valid, comment two chars longer
	    $self->{comment} .= chr($id3v1);
	    $self->{comment} .= chr($self->{track})
		if $self->{track} and $self->{track}!=32;
	    $self->{track} = '';
	};
	$self->{track} = '' unless $self->{track};
	$self->{genre} = id2genre($self->{genreID});
	if ($e = $self->get_config('decode_encoding_v1') and $e->[0]) {
	    my $field;
	    require Encode;

	    for $field (qw(title artist album comment)) {
	      $self->{$field} = Encode::decode($e->[0], $self->{$field});
	    }
	}
    }
}

# convert small integer id to genre name
sub id2genre {
    my $id=shift;
    return "" unless defined $id and $id < @winamp_genres;
    return $winamp_genres[$id];
}

# convert genre name to small integer id
sub genre2id {
    my $genre = MP3::Tag::Implemenation::_massage_genres(shift, 'num');
    return $genre if defined $genre;
    return 255;
}

# nothing to do for destroy
sub DESTROY {
}

1;

######## define all the genres

BEGIN { @mp3_genres = ( 'Blues', 'Classic Rock', 'Country', 'Dance',
			'Disco', 'Funk', 'Grunge', 'Hip-Hop', 'Jazz', 'Metal', 'New Age',
			'Oldies', 'Other', 'Pop', 'R&B', 'Rap', 'Reggae', 'Rock', 'Techno',
			'Industrial', 'Alternative', 'Ska', 'Death Metal', 'Pranks',
			'Soundtrack', 'Euro-Techno', 'Ambient', 'Trip-Hop', 'Vocal',
			'Jazz+Funk', 'Fusion', 'Trance', 'Classical', 'Instrumental', 'Acid',
			'House', 'Game', 'Sound Clip', 'Gospel', 'Noise', 'AlternRock',
			'Bass', 'Soul', 'Punk', 'Space', 'Meditative', 'Instrumental Pop',
			'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
			'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
			'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 
			'Christian Rap', 'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
			'Psychadelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal',
			'Acid Punk', 'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
			'Hard Rock', );

  	@winamp_genres = ( @mp3_genres, 'Folk', 'Folk-Rock', 
			   'National Folk', 'Swing', 'Fast Fusion', 'Bebob', 'Latin', 'Revival',
			   'Celtic', 'Bluegrass', 'Avantgarde', 'Gothic Rock',
			   'Progressive Rock', 'Psychedelic Rock', 'Symphonic Rock',
			   'Slow Rock', 'Big Band', 'Chorus', 'Easy Listening',
			   'Acoustic', 'Humour', 'Speech', 'Chanson', 'Opera', 
			   'Chamber Music', 'Sonata', 'Symphony', 'Booty Bass', 'Primus', 
			   'Porn Groove', 'Satire', 'Slow Jam', 'Club', 'Tango', 'Samba',
			   'Folklore', 'Ballad', 'Power Ballad', 'Rhythmic Soul',
			   'Freestyle', 'Duet', 'Punk Rock', 'Drum Solo', 'Acapella',
			   'Euro-House', 'Dance Hall',
			   # More from MP3::Info
			   'Goa', 'Drum & Bass', 'Club-House', 'Hardcore',
			   'Terror', 'Indie', 'BritPop', 'Negerpunk',
			   'Polsk Punk', 'Beat', 'Christian Gangsta Rap',
			   'Heavy Metal', 'Black Metal', 'Crossover',
			   'Contemporary Christian Music', 'Christian Rock',
			   'Merengue', 'Salsa', 'Thrash Metal', 'Anime',
			   'JPop', 'SynthPop',			# 149
			 ); 
}

=pod

=head1 SEE ALSO

L<MP3::Tag>, L<MP3::Tag::ID3v2>

ID3v1 standard - http://www.id3.org

=head1 COPYRIGHT

Copyright (c) 2000-2004 Thomas Geffert.  All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=cut
