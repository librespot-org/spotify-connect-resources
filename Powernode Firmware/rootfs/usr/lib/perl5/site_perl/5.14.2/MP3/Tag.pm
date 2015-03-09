
package MP3::Tag;

# Copyright (c) 2000-2004 Thomas Geffert.  All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the Artistic License, distributed
# with Perl.

################
#
# provides a general interface for different modules, which can read tags
#
# at the moment MP3::Tag works with MP3::Tag::ID3v1 and MP3::Tag::ID3v2

use strict;

{
  package MP3::Tag::__hasparent;
  sub parent_ok {
    my $self = shift;
    $self->{parent} and $self->{parent}->proxy_ok;
  }
  sub get_config {
    my $self = shift;
    return $MP3::Tag::config{shift()} unless $self->parent_ok;
    return $self->{parent}->get_config(@_);
  }
  *get_config1 = \&MP3::Tag::Implemenation::get_config1;
}

use MP3::Tag::ID3v1;
use MP3::Tag::ID3v2;
use MP3::Tag::File;
use MP3::Tag::Inf;
use MP3::Tag::CDDB_File;
use MP3::Tag::Cue;
use MP3::Tag::ParseData;
use MP3::Tag::ImageSize;
use MP3::Tag::ImageExifTool;
use MP3::Tag::LastResort;

use vars qw/$VERSION @ISA/;
$VERSION="1.13";
@ISA = qw( MP3::Tag::User MP3::Tag::Site MP3::Tag::Vendor
	   MP3::Tag::Implemenation ); # Make overridable
*config = \%MP3::Tag::Implemenation::config;

package MP3::Tag::Implemenation;	# XXXX Old mispring...
use vars qw/%config/;
%config = ( autoinfo			  => [qw( ParseData ID3v2 ID3v1 ImageExifTool
						 CDDB_File Inf Cue ImageSize
						 filename LastResort )],
	    cddb_files			  => [qw(audio.cddb cddb.out cddb.in)],
	    v2title			  => [qw(TIT1 TIT2 TIT3)],
	    composer			  => ['TCOM|a'],
	    performer			  => ['TXXX[TPE1]|TPE1|a'],
	    extension			  => ['\.(?!\d+\b)\w{1,4}$'],
	    parse_data			  => [],
	    parse_split			  => ["\n"],
	    encoded_v1_fits		  => [0],
	    parse_filename_ignore_case	  => [1],
	    parse_filename_merge_dots	  => [1],
	    parse_join			  => ['; '],
	    year_is_timestamp		  => [1],
	    comment_remove_date		  => [0],
	    id3v2_frame_empty_ok	  => [0],
	    id3v2_minpadding		  => [128],
	    id3v2_sizemult		  => [512],
	    id3v2_shrink		  => [0],
	    id3v2_mergepadding		  => [0],
	    id3v23_unsync_size_w	  => [0],
	    id3v23_unsync		  => [1],
	    parse_minmatch		  => [0],
	    update_length		  => [1],
	    default_language		  => ['XXX'],
	    default_descr_c		  => [''],
	    person_frames		  => [qw{ TEXT TCOM TXXX[TPE1] TPE1
						  TPE3 TOPE TOLY TMCL TIPL TENC
						  TXXX[person-file-by] }],
	    id3v2_frames_autofill	  => [qw{ TXXX[MCDI-fulltoc] 1 TXXX[cddb_id] 0
						  TXXX[cdindex_id] 0 }],
	    id3v2_set_trusted_encoding0	  => [1],
	    id3v2_fix_encoding_on_edit	  => [1],
	    name_for_field_normalization  => ['%{composer}'],
	    local_cfg_file		  => ['~/.mp3tagprc'],
	    extra_config_keys		  => [],
	    is_writable			  => ['writable_by_extension'],	
 # ExifTool says: ID3 may be in MP3/MPEG/AIFF/OGG/FLAC/APE/RealAudio (MPC).
	    writable_extensions		  => [qw(mp3 mp2 id3 tag ogg mpg mpeg
						 mp4 aiff flac ape ram mpc)],
	  );
{
  my %e;
  for my $t (qw(V1 V2 FILENAME FILES INF CDDB_FILE CUE)) {
    $e{$t} = $ENV{"MP3TAG_DECODE_${t}_DEFAULT"};
    $e{$t} = $ENV{MP3TAG_DECODE_DEFAULT}  unless defined $e{$t};
    $config{"decode_encoding_" . lc $t} = [$e{$t}] if $e{$t};
  }
  $e{eV1} = $ENV{MP3TAG_ENCODE_V1_DEFAULT};
  $e{eV1} = $ENV{MP3TAG_ENCODE_DEFAULT}	  unless defined $e{eV1};
  $e{eV1} = $e{V1}			  unless defined $e{eV1};
  $config{encode_encoding_v1} = [$e{eV1}] if $e{eV1};

  $e{eF} = $ENV{MP3TAG_ENCODE_FILES_DEFAULT};
  $e{eF} = $ENV{MP3TAG_ENCODE_DEFAULT}	  unless defined $e{eF};
  $e{eF} = $e{FILES}			  unless defined $e{eF};
  $config{encode_encoding_files} = [$e{eF}] if $e{eF};
}

=pod

=head1 NAME

MP3::Tag - Module for reading tags of MP3 audio files

=head1 SYNOPSIS

  use MP3::Tag;

  $mp3 = MP3::Tag->new($filename);

  # get some information about the file in the easiest way
  ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
  # Or:
  $comment = $mp3->comment();
  $dedicated_to
    = $mp3->select_id3v2_frame_by_descr('COMM(fre,fra,eng,#0)[dedicated to]');

  $mp3->title_set('New title');		# Edit in-memory copy
  $mp3->select_id3v2_frame_by_descr('TALB', 'New album name'); # Edit in memory
  $mp3->select_id3v2_frame_by_descr('RBUF', $n1, $n2, $n3);    # Edit in memory
  $mp3->update_tags({year => 1866});	# Edit in-memory, and commit to file
  $mp3->update_tags();			# Commit to file

The following low-level access code is discouraged; better use title()
etc., title_set() etc., update_tags(), select_id3v2_frame_by_descr()
etc. methods on the wrapper $mp3:

  # scan file for existing tags
  $mp3->get_tags;

  if (exists $mp3->{ID3v1}) {
      # read some information from the tag
      $id3v1 = $mp3->{ID3v1};  # $id3v1 is only a shortcut for $mp3->{ID3v1}
      print $id3v1->title;

      # change the tag contents
      $id3v1->all("Song","Artist","Album",2001,"Comment",10,"Top 40");
      $id3v1->write_tag;
  }

  if (exists $mp3->{ID3v2}) {
      # read some information from the tag
      ($name, $info) = $mp3->{ID3v2}->get_frame("TIT2");
      # delete the tag completely from the file
      $mp3->{ID3v2}->remove_tag;
  } else {
      # create a new tag
      $mp3->new_tag("ID3v2");
      $mp3->{ID3v2}->add_frame("TALB", "Album title");
      $mp3->{ID3v2}->write_tag;
  }

  $mp3->close();

Please consider using the script F<mp3info2>; it allows simple access
to most features of this module via command-line options; see
L<mp3info2>.

=head1 AUTHORS

Thomas Geffert, thg@users.sourceforge.net
Ilya Zakharevich, ilyaz@cpan.org

=head1 DESCRIPTION

C<MP3::Tag> is a wrapper module to read different tags of mp3 files.
It provides an easy way to access the functions of separate modules which
do the handling of reading/writing the tags itself.

At the moment MP3::Tag::ID3v1 and MP3::Tag::ID3v2 are supported for
read and write; MP3::Tag::ImageExifTool, MP3::Tag::Inf, MP3::Tag::CDDB_File,
MP3::Tag::File,  MP3::Tag::Cue, MP3::Tag::ImageSize, MP3::Tag::LastResort
are supported for read access (the information obtained by
L<Image::ExifTool|Image::ExifTool> (if present), parsing CDDB files,
F<.inf> file, the filename, and F<.cue> file, and obtained via
L<Image::Size|Image::Size>) (if present).

=over 4

=item new()

 $mp3 = MP3::Tag->new($filename);

Creates a mp3-object, which can be used to retrieve/set
different tags.

=cut

sub rel2abs ($) {
  shift;
  if (eval {require File::Spec; File::Spec->can('rel2abs')}) {
    File::Spec->rel2abs(shift);
  } else {
#    require Cwd;
#    Cwd::abs_path(shift);
    shift;
  }
}

sub new {
    my $class = shift;
    my $filename = shift;
    my $mp3data;
    my $self = {};
    bless $self, $class;
    my $proxy = MP3::Tag::__proxy->new($self);
    if (-f $filename or -c $filename) {
	$mp3data = MP3::Tag::File->new_with_parent($filename, $proxy);
    }
    # later it should hopefully possible to support also http/ftp sources
    # with a MP3::Tag::Net module or something like that
    if ($mp3data) {
	%$self = (filename	=> $mp3data,
		  ofilename	=> $filename,
		  abs_filename	=> $class->rel2abs($filename),
		  __proxy	=> $proxy);
	return $self;
    }
    return undef;
}

{ # Proxy class: to have only one place where to weaken/localize the reference
  # $obj->[0] must be settable to the handle (not needed if weakening succeeds)
  package MP3::Tag::__proxy;
  use vars qw/$AUTOLOAD/;

  my $skip_weaken = $ENV{MP3TAG_SKIP_WEAKEN};
  sub new {
    my ($class, $handle) = (shift,shift);
    my $self = bless [$handle], $class;
    #warn("weaken() failed, falling back"),
    return bless [], $class if $skip_weaken or not
      eval {require Scalar::Util; Scalar::Util::weaken($self->[0]); 1};
    $self;
  }
  sub DESTROY {}
  sub proxy_ok { shift->[0] }
  sub AUTOLOAD {
    my $self = shift;
    die "local_proxy not initialized" unless $self->[0];
    (my $meth = $AUTOLOAD) =~ s/.*:://;
    my $smeth = $self->[0]->can($meth);
    die "proxy can't find the method $meth" unless $smeth;
    unshift @_, $self->[0];
    goto &$smeth;
  }
}

sub proxy_ok { 1 }		# We can always be a proxy to ourselves... ;-)

=pod

=item get_tags()

  [old name: getTags() . The old name is still available, but its use is not advised]

  @tags = $mp3->get_tags;

Checks which tags can be found in the mp3-object. It returns
a list @tags which contains strings identifying the found tags, like
"ID3v1", "ID3v2", "Inf", or "CDDB_File" (the last but one if the F<.inf>
information file with the same basename as MP3 file is found).

Each found tag can then be accessed with $mp3->{tagname} , where tagname is
a string returned by get_tags ;

Use the information found in L<MP3::Tag::ID3v1>, L<MP3::Tag::ID3v2> and
L<MP3::Tag::Inf>, L<MP3::Tag::CDDB_File>, L<MP3::Tag::Cue> to see what you can do with the tags.

=cut 

################ tag subs

sub get_tags {
    my $self = shift;
    return @{$self->{gottags}} if exists $self->{gottags};
    my (@IDs, $id);

    # Will not create a reference loop
    local $self->{__proxy}[0] = $self unless $self->{__proxy}[0] or $ENV{MP3TAG_TEST_WEAKEN};
    for $id (qw(ParseData ID3v2 ID3v1 ImageExifTool Inf CDDB_File Cue ImageSize LastResort)) {
	my $ref = "MP3::Tag::$id"->new_with_parent($self->{filename}, $self->{__proxy});
	next unless defined $ref;
	$self->{$id} = $ref;
	push @IDs, $id;
    }
    $self->{gottags} = [@IDs];
    return @IDs;
}

sub _get_tag {
    my $self = shift;
    $self->{shift()};
}

# keep old name for a while
*getTags = \&get_tags;

=item new_fake

  $obj = MP3::Tag->new_fake();

This method produces a "fake" MP3::Tag object which behaves as an MP3
file without tags.  Give a TRUE optional argument if you want to set
some properties of this object.

=cut

sub new_fake {
    my ($class, $settable) = (shift, shift);
    my %h = (gottags => []);
    my $self = bless \%h, $class;
    if ($settable) {
      $h{__proxy} = MP3::Tag::__proxy->new($self);
      $h{ParseData} = MP3::Tag::ParseData->new_with_parent(undef, $h{__proxy});
    }
    \%h;
}


=pod

=item new_tag()

  [old name: newTag() . The old name is still available, but its use is not advised]

  $tag = $mp3->new_tag($tagname);

Creates a new tag of the given type $tagname. You
can access it then with $mp3->{$tagname}. At the
moment ID3v1 and ID3v2 are supported as tagname.

Returns an tag-object: $mp3->{$tagname}.

=cut

sub new_tag {
    my $self = shift;
    my $whichTag = shift;
    if ($whichTag =~ /1/) {
	$self->{ID3v1}= MP3::Tag::ID3v1->new($self->{filename},1);
	return $self->{ID3v1};
    } elsif ($whichTag =~ /2/) {
	$self->{ID3v2}= MP3::Tag::ID3v2->new($self->{filename},1);
	return $self->{ID3v2};
    }
}

# keep old name for a while
*newTag = \&new_tag;

#only as a shortcut to {filename}->close to explicitly close a file

=pod

=item close()

  $mp3->close;

You can use close() to explicitly close a file. Normally this is done
automatically by the module, so that you do not need to do this.

=cut

sub close {
    my $self=shift;
    $self->{filename}->close;
}

=pod

=item genres()

  $allgenres = $mp3->genres;
  $genreName = $mp3->genres($genreID);
  $genreID   = $mp3->genres($genreName);

Returns a list of all genres (reference to an array), or the according 
name or id to a given id or name.

This function is only a shortcut to MP3::Tag::ID3v1->genres.

This can be also called as MP3::Tag->genres;

=cut

sub genres {
  # returns all genres, or if a parameter is given, the according genre
  my $self=shift;
  return MP3::Tag::ID3v1::genres(shift);
}

=pod

=item autoinfo()

  ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
  $info_hashref = $mp3->autoinfo();

autoinfo() returns information about the title, track number,
artist, album name, the file comment, the year and genre.  It can get this
information from an ID3v1-tag, an ID3v2-tag, from CDDB file, from F<.inf>-file,
and from the filename itself.

It will as default first try to find a ID3v2-tag to get this
information. If this cannot be found it tries to find a ID3v1-tag, then
to read an CDDB file, an F<.inf>-file, and
if these are not present either, it will use the filename to retrieve
the title, track number, artist, album name.  The comment, year and genre
are found differently, via the C<comment>, C<year> and C<genre> methods.

You can change the order of lookup with the config() command.

autoinfo() returns an array with the information or a hashref. The hash
has four keys 'title', 'track', 'artist' and 'album' where the information is
stored.  If comment, year or genre are found, the hash will have keys
'comment' and/or 'year' and/or 'genre' too.

If an optional argument C<'from'> is given, the returned values (title,
track number, artist, album name, the file comment, the year and genre) are
array references with the first element being the value, the second the
tag (C<ID3v2> or C<ID3v1> or C<Inf> or C<CDDB_File> or C<Cue> or C<filename>) from which
it is taken.

(Deprecated name 'song' can be used instead of 'title' as well.)

=cut

sub autoinfo() {
    my ($self, $from) = (shift, shift);
    my (@out, %out);

    for my $elt ( qw( title track artist album comment year genre ) ) {
	my $out = $self->$elt($from);
	if (wantarray) {
	    push @out, $out;
	} elsif (defined $out and length $out) {
	    $out{$elt} = $out;
	}
    }
    $out{song} = $out{title} if exists $out{title};

    return wantarray ? @out : \%out;
}

=item comment()

  $comment = $mp3->comment();		# empty string unless found

comment() returns comment information. It can get this information from an
ID3v1-tag, or an ID3v2-tag (from C<COMM> frame with empty <short> field),
CDDB file (from C<EXTD> or C<EXTT> fields), or F<.inf>-file (from
C<Trackcomment> field).

It will as default first try to find a ID3v2-tag to get this
information. If no comment is found there, it tries to find it in a ID3v1-tag,
if none present, will try CDDB file, then F<.inf>-file.  It returns an empty string if
no comment is found.

You can change the order of this with the config() command.

If an optional argument C<'from'> is given, returns an array reference with
the first element being the value, the second the tag (ID3v2 or ID3v1) from
which the value is taken.

=cut

=item year()

  $year = $mp3->year();		# empty string unless found

year() returns the year information. It can get this information from an
ID3v2-tag, or ID3v1-tag, or F<.inf>-file, or filename.

It will as default first try to find a ID3v2-tag to get this
information. If no year is found there, it tries to find it in a ID3v1-tag,
if none present, will try CDDB file, then F<.inf>-file,
then by parsing the file name. It returns an empty string if no year is found.

You can change the order of this with the config() command.

If an optional argument C<'from'> is given, returns an array reference with
the first element being the value, the second the tag (ID3v2 or ID3v1 or
filename) from which the value is taken.

=item comment_collection(), comment_track(), title_track(). artist_collection()

access the corresponding fields returned by parse() method of CDDB_File.

=item cddb_id(), cdindex_id()

access the corresponding methods of C<ID3v2>, C<Inf> or C<CDDB_File>.

=item title_set(), artist_set(), album_set(), year_set(), comment_set(), track_set(), genre_set()

  $mp3->title_set($newtitle, [$force_id3v2]);

Set the corresponding value in ID3v1 tag, and, if the value does not fit,
or force_id3v2 is TRUE, in the ID3v2 tag.  Changes are made to in-memory
copy only.  To propagate to the file, use update_tags() or similar methods.

=item track1()

Same as track(), but strips trailing info: if track() returns C<3/12>
(which means track 3 of 12), this method returns C<3>.

=item track2()

Returns the second part of track number (compare with track1()).

=item track0()

Same as track1(), but pads with leading 0s to width of track2(); takes an
optional argument (default is 2) giving the pad width in absense of track2().

=item disk1(), disk2()

Same as track1(), track2(), but with disk-number instead of track-number
(stored in C<TPOS> ID3v2 frame).

=item disk_alphanum()

Same as disk1(), but encodes a non-empty result as a letter (1 maps to C<a>,
2 to C<b>, etc).  If number of disks is more than 26, falls back to numeric
(e.g, C<3/888> will be encoded as C<003>).

=cut

sub track1 ($) {
  my $r = track(@_);
  $r =~ s(/.*)()s;
  $r;
}

sub track2 ($) {
  my $r = track(@_);
  return '' unless $r =~ s(^.*?/)()s;
  $r;
}

sub track0 ($) {
  my $self = shift;
  my $d = (@_ ? shift() : 2);
  my $r = $self->track();
  return '' unless defined $r;
  (my $r1 = $r) =~ s(/.*)()s;
  $r = 'a' x $d unless $r =~ s(^.*?/)()s;
  my $l = length $r;
  sprintf "%0${l}d", $r1;
}

sub disk1 ($) {
  my $self = shift;
  my $r = $self->select_id3v2_frame('TPOS');
  return '' unless defined $r;
  $r =~ s(/.*)()s;
  $r;
}

sub disk2 ($) {
  my $self = shift;
  my $r = $self->select_id3v2_frame('TPOS');
  return '' unless defined $r;
  return '' unless $r =~ s(^.*?/)()s;
  $r;
}

sub disk_alphanum ($) {
  my $self = shift;
  my $r = $self->select_id3v2_frame('TPOS');
  return '' unless defined $r;
  (my $r1 = $r) =~ s(/.*)()s;
  $r = $r1 unless $r =~ s(^.*?/)()s;	# max(disk2, disk1)
  return chr(ord('a') - 1 + $r1) if $r <= 26;
  my $l = length $r;
  sprintf "%0${l}d", $r1;
}

my %ignore_0length = qw(ID3v1 1 CDDB_File 1 Inf 1 Cue 1 ImageSize 1 ImageExifTool 1);

sub auto_field($;$) {
    my ($self, $elt, $from) = (shift, shift, shift);
    local $self->{__proxy}[0] = $self unless $self->{__proxy}[0] or $ENV{MP3TAG_TEST_WEAKEN};

    my $parts = $self->get_config($elt) || $self->get_config('autoinfo');
    $self->get_tags;

    my $do_can = ($elt =~ /^(cd\w+_id|height|width|bit_depth|mime_type|img_type|_duration)$/);
    foreach my $part (@$parts) {
	next unless exists $self->{$part};
	next if $do_can and not $self->{$part}->can($elt);
	next unless defined (my $out = $self->{$part}->$elt());
	# Ignore 0-length answers from ID3v1, ImageExifTool, CDDB_File, Cue, ImageSize, and Inf
	next if not length $out and $ignore_0length{$part}; # These return ''
	return [$out, $part] if $from;
	return $out;
    }
    return '';
}

for my $elt ( qw( title track artist album comment year genre ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    my $self = shift;
    my $translate = ($self->get_config("translate_$elt") || [])->[0] || sub {$_[1]};
    return &$translate($self, $self->auto_field($elt, @_));
  }
}

my %hide_meth = qw(mime_type _mime_type);

for my $elt ( qw( cddb_id cdindex_id height width bit_depth mime_type img_type _duration ) ) {
  no strict 'refs';
  *{$hide_meth{$elt} || $elt} = sub (;$) {
    my $self = shift;
    return $self->auto_field($elt, @_);
  }
}

for my $elt ( qw( comment_collection comment_track title_track artist_collection ) ) {
  no strict 'refs';
  my ($tr) = ($elt =~ /^(\w+)_/);
  *$elt = sub (;$) {
    my $self = shift;
    local $self->{__proxy}[0] = $self unless $self->{__proxy}[0] or $ENV{MP3TAG_TEST_WEAKEN};
    $self->get_tags;
    return unless exists $self->{CDDB_File};
    my $v = $self->{CDDB_File}->parse($elt);
    return unless defined $v;
    my $translate = ($self->get_config("translate_$tr") || [])->[0] || sub {$_[1]};
    return &$translate( $self, $v );
  }
}

for my $elt ( qw(title artist album year comment track genre) ) {
  no strict 'refs';
  *{"${elt}_set"} = sub ($$;$) {
    my ($mp3, $val, $force2) = (shift, shift, shift);

    $mp3->get_tags;
    $mp3->new_tag("ID3v1") unless exists $mp3->{ID3v1};
    $mp3->{ID3v1}->$elt( $val );

    return 1
      if not $force2 and $mp3->{ID3v1}->fits_tag({$elt => $val})
	and not exists $mp3->{ID3v2};

    $mp3->new_tag("ID3v2") unless exists $mp3->{ID3v2};
    $mp3->{ID3v2}->$elt( $val );
  }
}

sub aspect_ratio ($) {
  my $self = shift;
  my ($w, $h) = ($self->width, $self->height);
  return unless $w and $h;
  $w/$h;
}

sub aspect_ratio_inverted ($) {
  my $r = shift->aspect_ratio or return;
  1/$r;
}

sub aspect_ratio3 ($) {
  my $r = shift->aspect_ratio();
  $r ? sprintf '%.3f', $r : $r;
}

=item mime_type( [$lazy] )

Returns the MIME type as a string.  Returns C<application/octet-stream>
for unrecognized types.  If not $lazy, will try harder (via ExifTool, if
needed).

=item mime_Pretype( [$lazy] )

Returns uppercased first component of MIME type.

=cut

sub mime_Pretype ($;$) {
  my $r = shift->mime_type(shift);
  $r =~ s,/.*,,s;
  ucfirst lc $r
}

sub mime_type ($;$) {		# _mime_type goes thru auto_field 'mime_type'
  my ($self, $lazy) = (shift, shift);
  $self->get_tags;
  my $h = $self->{header};
  my $t = $h && $self->_Data_to_MIME($h, 1);
  return $t if $t;
  return((!$lazy && $self->_mime_type()) || 'application/octet-stream');
}

=item genre()

  $genre = $mp3->genre();		# empty string unless found

genre() returns the genre string. It can get this information from an
ID3v2-tag or ID3v1-tag.

It will as default first try to find a ID3v2-tag to get this
information. If no genre is found there, it tries to find it in a ID3v1-tag,
if none present, will try F<.inf>-file,
It returns an empty string if no genre is found.

You can change the order of this with the config() command.

If an optional argument C<'from'> is given, returns an array reference with
the first element being the value, the second the tag (ID3v2 or ID3v1 or
filename) from which the value is taken.

=item composer()

  $composer = $mp3->composer();		# empty string unless found

composer() returns the composer.  By default, it gets from ID3v2 tag,
otherwise returns artist.

You can change the inspected fields with the config() command.
Subject to normalization via C<translate_composer> or
C<translate_person> configuration variables.

=item performer()

  $performer = $mp3->performer();		# empty string unless found

performer() returns the main performer.  By default, it gets from ID3v2
tag C<TXXX[TPE1]>, otherwise from ID3v2 tag C<TPE1>, otherwise
returns artist.

You can change the inspected fields with the config() command.
Subject to normalization via C<translate_performer> or
C<translate_person> configuration variables.

=cut

for my $elt ( qw( composer performer ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    my $self = shift;
    my $translate = ($self->get_config("translate_$elt")
		     || $self->get_config("translate_person")
		     || [])->[0] || sub {$_[1]};
    my $fields = ($self->get_config($elt))->[0];
    return &$translate($self, $self->interpolate("%{$fields}"));
  }
}

=item config

  MP3::Tag->config(item => value1, value2...);	# Set options globally
  $mp3->config(item => value1, value2...);	# Set object options

When object options are first time set or get, the global options are
propagated into object options.  (So if global options are changed later, these
changes are not inherited.)

Possible items are:

=over

=item autoinfo

Configure the order in which ID3v1-, ID3v2-tag and filename are used
by autoinfo.  The default is C<ParseData, ID3v2, ID3v1, ImageExifTool,
CDDB_File, Inf, Cue, ImageSize, filename, LastResort>.
Options can be elements of the default list.  The order
in which they are given to config also sets the order how they are
used by autoinfo. If an option is not present, it will not be used
by autoinfo (and other auto-methods if the specific overriding config
command were not issued).

  $mp3->config("autoinfo","ID3v1","ID3v2","filename");

sets the order to check first ID3v1, then ID3v2 and at last the
Filename

  $mp3->config("autoinfo","ID3v1","filename","ID3v2");

sets the order to check first ID3v1, then the Filename and last
ID3v2. As the filename will be always present ID3v2 will here
never be checked.

  $mp3->config("autoinfo","ID3v1","ID3v2");

sets the order to check first ID3v1, then ID3v2. The filename will
never be used.

=item title artist album year comment track genre

Configure the order in which ID3v1- and ID3v2-tag are used
by the corresponding methods (e.g., comment()).  Options can be
the same as for C<autoinfo>.  The order
in which they are given to config also sets the order how they are
used by comment(). If an option is not present, then C<autoinfo> option
will be used instead.

=item  extension

regular expression to match the file extension (including the dot).  The
default is to match 1..4 letter extensions which are not numbers.

=item  composer

string to put into C<%{}> to interpolate to get the composer.  Default
is C<'TCOM|a'>.

=item performer

string to put into C<%{}> to interpolate to get the main performer.
Default is C<'TXXX[TPE1]|TPE1|a'>.

=item parse_data

the data used by L<MP3::Tag::ParseData> handler; each option is an array
reference of the form C<[$flag, $string, $pattern1, ...]>.  All the options
are processed in the following way: patterns are matched against $string
until one of them succeeds; the information obtained from later options takes
precedence over the information obtained from earlier ones.

=item  parse_split

The regular expression to split the data when parsing with C<n> or C<l> flags.

=item  parse_filename_ignore_case

If true (default), calling parse() and parse_rex() with match-filename
escapes (such as C<%=D>) matches case-insensitively.

=item  parse_filename_merge_dots

If true (default), calling parse() and parse_rex() with match-filename
escapes (such as C<%=D>) does not distinguish a dot and many consequent
dots.

=item  parse_join

string to put between multiple occurences of a tag in a parse pattern;
defaults to C<'; '>.  E.g., parsing C<'1988-1992, Homer (LP)'> with pattern
C<'%c, %a (%c)'> results in comment set to C<'1988-1992; LP'> with the
default value of C<parse_join>.

=item  v2title

Configure the elements of ID3v2-tag which are used by ID3v2::title().
Options can be "TIT1", "TIT2", "TIT3"; the present values are combined.
If an option is not present, it will not be used by ID3v2::title().

=item  cddb_files

List of files to look for in the directory of MP3 file to get CDDB info.

=item  year_is_timestamp

If TRUE (default) parse() will match complicated timestamps against C<%y>;
for example, C<2001-10-23--30,2002-02-28> is a range from 23rd to 30th of
October 2001, I<and> 28th of February of 2002.  According to ISO, C<--> can
be replaced by C</> as well.  For convenience, the leading 0 can be omited
from the fields which ISO requires to be 2-digit.

=item  comment_remove_date

When extracting the date from comment fields, remove the recognized portion
even if it is human readable (e.g., C<Recorded on 2014-3-23>) if TRUE.
Current default: FALSE.

=item default_language

The language to use to select ID3v2 frames, and to choose C<COMM>
ID3v2 frame accessed in comment() method (default is 'XXX'; if not
C<XXX>, this should be lowercase 3-letter abbreviation according to
ISO-639-2).

=item default_descr_c

The description field used to choose the C<COMM> ID3v2 frame accessed
in comment() method.  Defaults to C<''>.

=item  id3v2_frame_empty_ok

When setting the individual id3v2 frames via ParseData, do not
remove the frames set to an empty string.  Default 0 (empty means 'remove').

=item id3v2_minpadding

Minimal padding to reserve after ID3v2 tag when writing (default 128),

=item id3v2_sizemult

Additionally to C<id3v2_minpadding>, insert padding to make file size multiple
of this when writing ID3v2 tag (default 512),  Should be power of 2.

=item id3v2_shrink

If TRUE, when writing ID3v2 tag, shrink the file if needed (default FALSE).

=item id3v2_mergepadding

If TRUE, when writing ID3v2 tag, consider the 0-bytes following the
ID3v2 header as writable space for the tag (default FALSE).

=item update_length

If TRUE, when writing ID3v2 tag, create a C<TLEN> tag if the duration
is known (as it is after calling methods like C<total_secs>, or
interpolation the duration value).  If this field is 2 or more, force
creation of ID3v2 tag by update_tags() if the duration is known.

=item  translate_*

FALSE, or a subroutine used to munch a field C<*> (out of C<title
track artist album comment year genre comment_collection comment_track
title_track artist_collection person>) to some "normalized" form.
Takes two arguments: the MP3::Tag object, and the current value of the
field.

The second argument may also have the form C<[value, handler]>, where
C<handler> is the string indentifying the handler which returned the
value.

=item short_person

Similar to C<translate_person>, but the intent is for this subroutine
to translate a personal name field to a shortest "normalized" form.

=item  person_frames

list of ID3v2 frames subject to normalization via C<translate_person>
handler; current default is C<TEXT TCOM TXXX[TPE1] TPE1 TPE3 TOPE TOLY
TMCL TIPL TENC TXXX[person-file-by]>.
Used by select_id3v2_frame_by_descr(), frame_translate(),
frames_translate().

=item id3v2_missing_fatal

If TRUE, interpolating ID3v2 frames (e.g., by C<%{TCOM}>) when
the ID3v2 tags is missing is a fatal error.  If false (default), in such cases
interpolation results in an empty string.

=item id3v2_recalculate

If TRUE, interpolating the whole ID3v2 tag (by C<%{ID3v2}>) will recalculate
the tag even if its contents is not modified.

=item parse_minmatch

may be 0, 1, or a list of C<%>-escapes (matching any string) which should
matched non-greedily by parse() and friends.  E.g., parsing 
C<'Adagio - Andante - Piano Sonata'> via C<'%t - %l'> gives different results
for the settings 0 and 1; note that greediness of C<%l> does not matter,
thus the value of 1 is equivalent for the value of C<t> for this particular
pattern.

=item id3v23_unsync_size_w

Old experimental flag to test why ITunes refuses to handle unsyncronized tags
(does not help, see L<id3v23_unsync>).  The idea was that
version 2.3 of the standard is not clear about frame size field, whether it
is the size of the frame after unsyncronization, or not.  We assume
that this size is one before unsyncronization (as in v2.2).
Setting this value to 1 will assume another interpretation (as in v2.4) for
write.

=item id3v23_unsync

Some broken MP3 players (e.g., ITunes, at least up to v6) refuse to
handle unsyncronized (i.e., written as the standard requires it) tags;
they may need this to be set to FALSE.  Default: TRUE.

(Some details: by definition, MP3 files should contain combinations of bytes
C<FF F*> or C<FF E*> only at the start of audio frames ("syncronization" points).
ID3v2 standards take this into account, and supports storing raw tag data
in a format which does not contain these combinations of bytes
[via "unsyncronization"].  Itunes etc do not only emit broken MP3 files
[which cause severe hiccups in players which do not know how to skip ID3v2
tags, as most settop DVD players], they also refuse to read ID3v2 tags
written in a correct, unsyncronized, format.)

(Note also that the issue of syncronization is also applicable to ID3v1
tags; however, since this data is near the end of the file, many players
are able to recognize that the syncronization points in ID3v1 tag cannot
start a valid frame, since there is not enough data to read; some other
players would hiccup anyway if ID3v1 contains these combinations of bytes...)

=item encoded_v1_fits

If FALSE (default), data containing "high bit characters" is considered to
not fit ID3v1 tag if one of the following conditions hold:

=over 4

=item 1.

C<encode_encoding_v1> is set (so the resulting ID3v1 tag is not
standard-complying, thus ambiguous without ID3v2), or

=item 2.

C<encode_encoding_v1> is not set, but C<decode_encoding_v1> is set
(thus read+write operation is not idempotent for ID3v1 tag).

=back

With the default setting, these problems are resolved as far as (re)encoding
of ID3v2 tag is non-ambiguous (which holds with the default settings for
ID3v2 encodeing).

=item decode_encoding_v1

=item encode_encoding_v1

=item decode_encoding_v2

=item decode_encoding_filename

=item decode_encoding_inf

=item decode_encoding_cddb_file

=item decode_encoding_cue

=item decode_encoding_files

=item encode_encoding_files

Encodings of C<ID3v1>, non-Unicode frames of C<ID3v2>, filenames,
external files, F<.inf> files, C<CDDB> files, F<.cue> files,
and user-specified files correspondingly.  The value of 0 means "latin1".

The default values for C<decode_encoding_*> are set from the
corresponding C<MP3TAG_DECODE_*_DEFAULT> environment variable (here
C<*> stands for the uppercased last component of the name); if this
variable is not set, from C<MP3TAG_DECODE_DEFAULT>.  Likewise, the
default value for C<encode_encoding_v1> is set from
C<MP3TAG_ENCODE_V1_DEFAULT> or C<MP3TAG_ENCODE_DEFAULT>; if not
present, from the value for C<decode_encoding_v1>; similarly for
C<encode_encoding_files>.

Note that C<decode_encoding_v2> has no "encode" pair; it may also be disabled
per tag via effects of C<ignore_trusted_encoding0_v2> and the corresponding
frame C<TXXX[trusted_encoding0_v2]> in the tag.  One should also keep in
mind that the ID3v1 standard requires the encoding to be "latin1" (so
does not store the encoding anywhere); this does not make a lot of sense,
and a lot of effort of this module is spend to fix this unfortunate flaw.
See L<"Problems with ID3 format">.

=item ignore_trusted_encoding0_v2

If FALSE (default), and the frame C<TXXX[trusted_encoding0_v2]> is set to TRUE,
the setting of C<decode_encoding_v2> is ignored.

=item id3v2_set_trusted_encoding0

If TRUE (default), and frames are converted from the given C<decode_encoding_v2>
to a standard-conforming encoding, a frame C<TXXX[trusted_encoding0_v2]> with
a TRUE value is added.

[The purpose is to make multi-step update in presence of C<decode_encoding_v2>
possible; with C<id3v2_set_trusted_encoding0> TRUE, and
C<ignore_trusted_encoding0_v2> FALSE (both are default values), editing of tags
can be idempotent.]

=item id3v2_fix_encoding_on_write

If TRUE and C<decode_encoding_v2> is defined, the ID3v2 frames are converted
to standard-conforming encodings on write.  The default is FALSE.

=item id3v2_fix_encoding_on_edit

If TRUE (default) and C<decode_encoding_v2> is defined (and not disabled
via a frame C<TXXX[trusted_encoding0_v2]> and the setting
C<ignore_trusted_encoding0_v2>), a CYA action is performed when an
edit may result in a confusion.  More precise, adding an ID3v2 frame which
is I<essentially> affected by C<decode_encoding_v2> would convert other
frames to a standard-conforming encoding (and would set
C<TXXX[trusted_encoding0_v2]> if required by C<id3v2_set_trusted_encoding0>).

Recall that the added frames are always encoded in standard-conformant way;
the action above avoids mixing non-standard-conformant frames with
standard-conformant frames.  Such a mix could not be cleared up by setting
C<decode_encoding_v2>!  One should also keep in mind that this does not affect
frames which contain characters above C<0x255>; such frames are always written
in Unicode, thus are not affected by C<decode_encoding_v2>.

=item id3v2_frames_autofill

Hash of suggested ID3v2 frames to autogenerate basing on extra information
available; keys are frame descriptors (such as C<TXXX[cddb_id]>), values
indicate whether ID3v2 tag should be created if it was not present.

This variable is inspected by the method C<id3v2_frames_autofill>,
which is not called automatically when the tag is accessed, but may be called
by scripts using the module.

The default is to force creation of tag for C<TXXX[MCDI-fulltoc]> frame, and do not
force creation for C<TXXX[cddb_id]> and C<TXXX[cdindex_id]>.

=item local_cfg_file

Name of configuration file read at startup by the method parse_cfg(); is
C<~>-substituted; defaults to F<~/.mp3tagprc>.

=item prohibit_v24

If FALSE (default), reading of ID3v2.4 is allowed (it is not fully supported,
but most things work acceptably).

=item write_v24

If FALSE (default), writing of ID3v2.4 is prohibited (it is not fully
supported; allow on your own risk).

=item name_for_field_normalization

interpolation of this string is used as a person name to normalize
title-like fields.  Defaults to C<%{composer}>.

=item extra_config_keys

List of extra config keys (default is empty); setting these would not cause
warnings, and would not affect operation of C<MP3::Tag>.  Applications using
this module may add to this list to allow their configuration by the same
means as configuration of C<MP3::Tag>.

=item is_writable

Contains a boolean value, or a method name and argument list
to call whether the tag may be added to the file.  Defaults to
writable_by_extension().

=item writable_extensions

Contains a list of extensions (case insensitive) for which the tag may be
added to the file.  Current default is C<mp3 mp2 id3 tag ogg mpg mpeg
mp4 aiff flac ape ram mpc> (extracted from L<ExifTool> docs; may be tuned
later).

=item *

Later there will be probably more things to configure.

=back

=cut

my $conf_rex;

sub config {
    my ($self, $item, @options) = @_;
    $item = lc $item;
    my $config = ref $self ? ($self->{config} ||= {%config}) : \%config;
    my @known = qw(autoinfo title artist album year comment track genre
		   v2title cddb_files force_interpolate parse_data parse_split
		   composer performer default_language default_descr_c
		   update_length id3v2_fix_encoding_on_write
		   id3v2_fix_encoding_on_edit extra_config_keys
		   parse_join parse_filename_ignore_case encoded_v1_fits
		   parse_filename_merge_dots year_is_timestamp
		   comment_remove_date extension id3v2_missing_fatal
		   id3v2_frame_empty_ok id3v2_minpadding id3v2_sizemult
		   id3v2_shrink id3v2_mergepadding person_frames short_person
		   parse_minmatch id3v23_unsync id3v23_unsync_size_w
		   id3v2_recalculate ignore_trusted_encoding0_v2
		   id3v2_set_trusted_encoding0 write_v24 prohibit_v24
		   encode_encoding_files encode_encoding_v1 encode_encoding_cue
		   decode_encoding_v1 decode_encoding_v2
		   decode_encoding_filename decode_encoding_files
		   decode_encoding_inf decode_encoding_cddb_file
		   name_for_field_normalization is_writable writable_extensions
		   id3v2_frames_autofill local_cfg_file);
    my @tr = map "translate_$_", qw( title track artist album comment
				     year genre comment_collection
				     comment_track title_track
				     composer performer
				     artist_collection person );
    my $e_known = $self->get_config('extra_config_keys');
    $e_known = [map lc, @$e_known];
    $conf_rex = '^(' . join('|', @known, @$e_known, @tr) . ')$' unless $conf_rex;

    if ($item =~ /^(force)$/) {
	return $config->{$item} = {@options};
    } elsif ($item !~ $conf_rex) {
	warn "MP3::Tag::config(): Unknown option '$item' found; known options: @known @$e_known @tr\n REX = <<<$conf_rex>>>\n";
	return;
    }
    undef $conf_rex if $item eq 'extra_config_keys';

    $config->{$item} = \@options;
}

=item get_config

  $opt_array = $mp3->get_config("item");

When object options are first time set or get, the global options are
propagated into object options.  (So if global options are changed later, these
changes are not inherited.)

=item get_config1

  $opt = $mp3->get_config1("item");

Similar to get_config(), but returns UNDEF if no config array is present, or
the first entry of array otherwise.

=cut

sub get_config ($$) {
    my ($self, $item) = @_;
    my $config = ref $self ? ($self->{config} ||= {%config}) : \%config;
    $config->{lc $item};
}

sub get_config1 {
  my $self = shift;
  my $c = $self->get_config(@_);
  $c and $c->[0];
}

=item name_for_field_normalization

  $name = $mp3->name_for_field_normalization;

Returns "person name" to use for normalization of title-like fields;
it is the result of interpolation of the configuration variable
C<name_for_field_normalization> (defaults to C<%{composer}> - which, by
default, expands the same as C<%{TCOM|a}>).

=cut

sub name_for_field_normalization ($) {
  my $self = shift;
  $self->interpolate( $self->get_config1("name_for_field_normalization") );
}

=item pure_filetags

  $data = $mp3->pure_filetags()->autoinfo;

Configures $mp3 to not read anything except the pure ID3v2 or ID3v1 tags, and
do not postprocess them.  Returns the object reference itself to simplify
chaining of method calls.

=cut

sub pure_filetags ($) {
    my $self = shift;
    for my $c (qw(autoinfo title artist album year comment track genre)) {
	$self->config($c,"ID3v2","ID3v1");
    }
    $self->config('comment_remove_date', 0);
    for my $k (%{$self->{config}}) {
	delete $self->{config}->{$k} if $k =~ /^translate_/;
    }
    return $self;
}

=item get_user

  $data = $mp3->get_user($n);	# n-th piece of user scratch space

Queries an entry in a scratch array ($n=3 corresponds to C<%{U3}>).

=item set_user

  $mp3->set_user($n, $data);	# n-th piece of user scratch space

Sets an entry in a scratch array ($n=3 corresponds to C<%{U3}>).

=cut

sub get_user ($$) {
    my ($self, $item) = @_;
    unless ($self->{userdata}) {
        local $self->{__proxy}[0] = $self unless $self->{__proxy}[0] or $ENV{MP3TAG_TEST_WEAKEN};
	$self->{ParseData}->parse('track');	# Populate the hash if possible
	$self->{userdata} ||= [];
    }
    return unless defined (my $d = $self->{userdata}[$item]);
    $d;
}

sub set_user ($$$) {
    my ($self, $item, $val) = @_;
    $self->{userdata} ||= [];
    $self->{userdata}[$item] = $val;
}

=item set_id3v2_frame

  $mp3->set_id3v2_frame($name, @values);

When called with only $name as the argument, removes the specified
frame (if it existed).  Otherwise sets the frame passing the specified
@values to the add_frame() function of MP3::Tag::ID3v2.  (The old value is
removed.)

=cut

# With two elements, removes frame
sub set_id3v2_frame ($$;@) {
    my ($self, $item) = (shift, shift);
    $self->get_tags;
    return if not @_ and not exists $self->{ID3v2};
    $self->new_tag("ID3v2") unless exists $self->{ID3v2};
    $self->{ID3v2}->remove_frame($item)
      if defined $self->{ID3v2}->get_frame($item);
    return unless @_;
    return $self->{ID3v2}->add_frame($item, @_);
}

=item get_id3v2_frames

  ($descr, @frames) = $mp3->get_id3v2_frames($fname);

Returns the specified frame(s); has the same API as
L<MP3::Tag::ID3v2::get_frames>, but also returns undef if no ID3v2
tag is present.

=cut

sub get_id3v2_frames ($$;$) {
    my ($self) = (shift);
    $self->get_tags;
    return if not exists $self->{ID3v2};
    $self->{ID3v2}->get_frames(@_);
}

=item delete_tag

  $deleted = $mp3->delete_tag($tag);

$tag should be either C<ID3v1> or C<ID3v2>.  Deletes the tag if it is present.
Returns FALSE if the tag is not present.

=cut

sub delete_tag ($$) {
    my ($self, $tag) = (shift, shift);
    $self->get_tags;
    die "Unexpected tag type '$tag'" unless $tag =~ /^ID3v[12]$/;
    return unless exists $self->{$tag};
    my $res = $self->{$tag}->remove_tag();
    $res = ($res >= 0) if $tag eq 'ID3v1'; # -1 on error
    $res or die "Error deleting tag `$tag'";
}

=item is_id3v2_modified

  $frame = $mp3->is_id3v2_modified();

Returns TRUE if ID3v2 tag exists and was modified after creation.

=cut

sub is_id3v2_modified ($$;@) {
    my ($self) = (shift);
    return if not exists $self->{ID3v2};
    $self->{ID3v2}->is_modified();
}

=item select_id3v2_frame

  $frame = $mp3->select_id3v2_frame($fname, $descrs, $langs [, $VALUE]);

Returns the specified frame(s); has the same API as
L<MP3::Tag::ID3v2/frame_select> (args are the frame name, the list of
wanted Descriptors, list of wanted Languages, and possibly the new
contents - with C<undef> meaning deletion).  For read-only access it
returns empty if no ID3v2 tag is present, or no frame is found.

If new contents is specified, B<ALL> the existing frames matching the
specification are deleted.

=item have_id3v2_frame

  $have_it = $mp3->have_id3v2_frame($fname, $descrs, $langs);

Returns TRUE the specified frame(s) exist; has the same API as
L<MP3::Tag::ID3v2::frame_have> (args are frame name, list of wanted
Descriptors, list of wanted Languages).

=item get_id3v2_frame_ids

  $h = $mp3->get_id3v2_frame_ids();
  print "  $_ => $h{$_}" for keys %$h;

Returns a hash reference with the short names of ID3v2 frames present
in the tag as keys (and long description of the meaning as values), or
FALSE if no ID3v2 tag is present.  See
L<MP3::Tags::ID3v2::get_frame_ids> for details.

=item id3v2_frame_descriptors

Returns the list of human-readable "long names" of frames (such as
C<COMM(eng)[lyricist birthdate]>), appropriate for interpolation, or
for select_id3v2_frame_by_descr().

=item select_id3v2_frame_by_descr

=item have_id3v2_frame_by_descr

Similar to select_id3v2_frame(), have_id3v2_frame(), but instead of
arguments $fname, $descrs, $langs take one string of the form

  NAME(langs)[descr]

Both C<(langs)> and C<[descr]> parts may be omitted; langs should
contain comma-separated list of needed languages.  The semantic is
similar to
L<MP3::Tag::ID3v2::frame_select_by_descr_simpler|MP3::Tag::ID3v2/frame_select_by_descr_simpler>.

It is allowed to have C<NAME> of the form C<FRAMnn>; C<nn>-th frame
with name C<FRAM> is chosen (C<-1>-based: the first frame is C<FRAM>,
the second C<FRAM00>, the third C<FRAM01> etc; for more user-friendly
scheme, use C<langs> of the form C<#NNN>, with C<NNN> 0-based; see
L<MP3::Tag::ID3v2/"get_frame_ids()">).

  $frame = $mp3->select_id3v2_frame_by_descr($descr [, $VALUE1, ...]);
  $have_it = $mp3->have_id3v2_frame_by_descr($descr);

select_id3v2_frame_by_descr() will also apply the normalizer in config
setting C<translate_person> if the frame name matches one of the
elements of the configuration setting C<person_frames>.

  $c = $mp3->select_id3v2_frame_by_descr("COMM(fre,fra,eng,#0)[]");
  $t = $mp3->select_id3v2_frame_by_descr("TIT2");
       $mp3->select_id3v2_frame_by_descr("TIT2", "MyT"); # Set/Change
       $mp3->select_id3v2_frame_by_descr("RBUF", $n1, $n2, $n3); # Set/Change
       $mp3->select_id3v2_frame_by_descr("RBUF", "$n1;$n2;$n3"); # Set/Change
       $mp3->select_id3v2_frame_by_descr("TIT2", undef); # Remove

Remember that when select_id3v2_frame_by_descr() is used for
modification, B<ALL> found frames are deleted before a new one is
added.  For gory details, see L<MP3::Tag::ID3v2/frame_select>.

=item frame_translate

  $mp3->frame_translate('TCOM'); # Normalize TCOM ID3v2 frame

assuming that the frame value denotes a person, normalizes the value
using personal name normalization logic (via C<translate_person>
configuration value).  Frame is updated, but the tag is not written
back.  The frame must be in the list of personal names frames
(C<person_frames> configuration value).

=item frames_translate

Similar to frame_translate(), but updates all the frames in
C<person_frames> configuration value.

=cut

sub select_id3v2_frame ($$;@) {
    my ($self) = (shift);
    $self->get_tags;
    if (not exists $self->{ID3v2}) {
	return if @_ <= 3 or not defined $_[3];	# Read access, or deletion
	$self->new_tag("ID3v2");
    }
    $self->{ID3v2}->frame_select(@_);
}

sub _select_id3v2_frame_by_descr ($$$;@) {
    my ($self, $update) = (shift, shift);
    $self->get_tags;
    if (not exists $self->{ID3v2}) {
	return if @_ <= 1 or @_ <= 2 and not defined $_[1]; # Read or delete
	$self->new_tag("ID3v2");
    }
    my $fname = $_[0];
    $fname =~ s/^(\w{4})\d+/$1/; # if FRAMnn, convert to FRAM
    my $tr = ($self->get_config('translate_person') || [])->[0];
    if ($tr) {
      my $translate = $self->get_config('person_frames');
      unless (ref $translate eq 'HASH') { # XXXX Store the hash somewhere???
	$translate = {map +($_, 1), @$translate};
	#$self->config('person_frames', @translate);
      }
      my $do = $translate->{$fname};
      $do = $translate->{$fname} # Remove language
	if not $do and $fname =~ s/^(\w{4})(?:\(([^()]*(?:\([^()]+\)[^()]*)*)\))/$1/;
      undef $tr unless $do;
    }
    return if $update and not $tr;
    $tr ||= sub {$_[1]};
    return $self->{ID3v2}->frame_select_by_descr_simpler(@_)
      if @_ > 2 or @_ == 2 and not defined $_[1]; # Multi-arg write or delete
    return $self->{ID3v2}->frame_select_by_descr_simpler(
	   $_[0], &$tr($self, $_[1])
	) if @_ == 2; # Write access with one arg

    my $val = $self->{ID3v2}->frame_select_by_descr_simpler(@_);
    my $nval;
    $nval = &$tr($self, $val) if defined $val;
    return $nval unless $update;
    # Update logic:
    return if not defined $val or $val eq $nval;
    $self->{ID3v2}->frame_select_by_descr_simpler($_[0], $nval);
}

sub select_id3v2_frame_by_descr ($$;@) {
    my ($self) = (shift);
    return $self->_select_id3v2_frame_by_descr(0, @_);
}

sub frame_translate ($@) {
    my ($self) = (shift);
    return $self->_select_id3v2_frame_by_descr(1, @_);
}

sub frames_translate ($) {
    my ($self) = (shift);
    for my $f (@{$self->get_config('person_frames') || []}) {
      $self->frame_translate($f);
    }
}

sub have_id3v2_frame ($$;@) {
    my ($self) = (shift);
    $self->get_tags;
    return if not exists $self->{ID3v2};
    $self->{ID3v2}->frame_have(@_);
}

sub have_id3v2_frame_by_descr ($$) {
    my ($self) = (shift);
    $self->get_tags;
    return if not exists $self->{ID3v2};
    $self->{ID3v2}->frame_have_by_descr(shift);
}

sub get_id3v2_frame_ids ($$) {
    my ($self) = (shift);
    $self->get_tags;
    return if not exists $self->{ID3v2};
    $self->{ID3v2}->get_frame_ids(@_);
}

sub id3v2_frame_descriptors ($) {
    my ($self) = (shift);
    $self->get_tags;
    return if not exists $self->{ID3v2};
    $self->{ID3v2}->get_frame_descriptors(@_);
}

=item copy_id3v2_frames($from, $to, $overwrite, [$keep_flags, $f_ids])

Copies specified frames between C<MP3::Tag> objects $from, $to.  Unless
$keep_flags, the copied frames have their flags cleared.
If the array reference $f_ids is not specified, all the frames (but C<GRID>
and C<TLEN>) are considered (subject to $overwrite), otherwise $f_ids should
contain short frame ids to consider. Group ID flag is always cleared.

If $overwrite is C<'delete'>, frames with the same descriptors (as
returned by get_frame_descr()) in $to are deleted first, then all the
specified frames are copied.  If $overwrite is FALSE, only frames with
descriptors not present in $to are copied.  (If one of these two
conditions is not met, the result may be not conformant to standards.)

Returns count of copied frames.

=cut

sub copy_id3v2_frames {
  my ($from, $to, $overwrite, $keep_flags, $f_ids) = @_;
  $from->get_tags;
  return 0 unless $from = $from->{ID3v2}; # No need to create it...
  $f_ids ||= [keys %{$from->get_frame_ids}];
  return 0 unless @$f_ids;
  $to->get_tags;
  $to->new_tag("ID3v2") if not exists $to->{ID3v2};
  $from->copy_frames($to->{ID3v2}, $overwrite, $keep_flags, $f_ids);
}

sub _Data_to_MIME ($$;$) {
    goto &MP3::Tag::ID3v2::_Data_to_MIME
}

=item _Data_to_MIME

Internal method to extract MIME type from a string the image file content.
Returns C<application/octet-stream> for unrecognized data
(unless extra TRUE argument is given).

  $format = $id3->_Data_to_MIME($data);

Currently, only the first 4 bytes of the string are inspected.

=cut


=item shorten_person

  $string = $mp3->shorten_person($person_name);

shorten $person_name as a personal name (according to C<short_person>
configuration setting).

=cut

sub shorten_person ($$) {
  my $self = shift;
  my $tr = ($self->get_config('short_person') || [])->[0];
  return shift unless $tr;
  return &$tr($self, shift);
}

=item normalize_person

  $string = $mp3->normalize_person($person_name);

normalize $person_name as a personal name (according to C<translate_person>
configuration setting).

=cut

sub normalize_person ($$) {
  my $self = shift;
  my $tr = ($self->get_config('translate_person') || [])->[0];
  return shift unless $tr;
  return &$tr($self, shift);
}


=item id3v2_frames_autofill

  $mp3->id3v2_frames_autofill($force);

Generates missing tags from the list specified in C<id3v2_frames_autofill>
configuration variable.  The tags should be from a short list this method
knows how to deal with:

  TXXX[MCDI-fulltoc]:	filled from file audio_cd.toc in directory of the
			audio file.  [Create this file with
			  readcd -fulltoc dev=0,1,0 -f=audio_cd >& nul
			 modifying the dev (and redirection per your shell). ]
  TXXX[cddb_id]
  TXXX[cdindex_id]:	filled from the result of the corresponding method
				(which may extract from .inf or cddb files).

Existing frames are not modified unless $force option is specified; when
$force is true, ID3v2 tag will be created even if it was not present.

=cut

sub id3v2_frames_autofill ($$) {
  my ($self, $forceframe) = (shift, shift);
  my %force = @{$self->get_config('id3v2_frames_autofill')};
  $self->get_tags;
  unless ($self->{ID3v2} or $forceframe) {	# first run: force ID3v2?
    for my $tag (keys %force) {
      next unless $force{$tag};
      my $v;
      $v = $self->$1() or next if $tag =~ /^TXXX\[(cd(?:db|index)_id)\]$/;
      if ($tag eq 'TXXX[MCDI-fulltoc]') {
	my $file = $self->interpolate('%D/audio_cd.toc');
	$v = -e $file;
      }
      $forceframe = 1, last if $v
    }
  }
  for my $tag (keys %force) {
    next if $self->have_id3v2_frame_by_descr($tag) and not $forceframe;
    next unless $force{$tag} or $self->{ID3v2} or $forceframe;
    my $v;
    $v = $self->$1() or next if $tag =~ /^TXXX\[(cd(?:db|index)_id)\]$/;
    if ($tag eq 'TXXX[MCDI-fulltoc]') {
      my $file = $self->interpolate('%D/audio_cd.toc');
      next unless -e $file;
      warn(<<EOW), next unless $self->track;
Could deduce MCDI info, but per id3v2.4 specs, must know the track number!
EOW
      eval {
	open F, "< $file" or die "Can't open `$file' for read: $!";
	binmode F or die "Can't binmode `$file' for read: $!";
	local $/;
	$v = <F>;
	CORE::close F or die "Can't close `$file' for read: $!";
      } or warn($@), next;
    }
    $self->select_id3v2_frame_by_descr($tag, $v), next if defined $v;
    die "id3v2_frames_autofill(): do not know how to create frame `$tag'";
  }
}

=item interpolate

  $string = $mp3->interpolate($pattern)

interpolates C<%>-escapes in $pattern using the information from $mp3 tags.
The syntax of escapes is similar to this of sprintf():

  % [ [FLAGS] MINWIDTH] [.MAXWIDTH] ESCAPE

The only recognized FLAGS are C<-> (to denote left-alignment inside MINWIDTH-
wide field), C<' '> (SPACE), and C<0> (denoting the fill character to use), as
well as an arbitrary character in parentheses (which becomes the fill
character).  MINWIDTH and MAXWIDTH should be numbers.

The short ESCAPEs are replaced by

		% => literal '%'
		t => title
		a => artist
		l => album
		y => year
		g => genre
		c => comment
		n => track
		f => filename without the directory path
		F => filename with the directory path
		D => the directory path of the filename
		E => file extension
		e => file extension without the leading dot
		A => absolute filename without extension
		B => filename without the directory part and extension
		N => filename as originally given without extension

		v	mpeg_version
		L	mpeg_layer_roman
		r	bitrate_kbps
		q	frequency_kHz
		Q	frequency_Hz
		S	total_secs_int
		M	total_millisecs_int
		m	total_mins
		mL	leftover_mins
		H	total_hours
		s	leftover_secs
		SL	leftover_secs_trunc
		ML	leftover_msec
		SML	leftover_secs_float
		C	is_copyrighted_YN
		p	frames_padded_YN
		o	channel_mode
		u	frames

		h	height	(these 3 for image files, Image::Size or Image::ExifData required)
		w	width
		iT	img_type
		mT	mime_type
		mP	mime_Pretype (the capitalized first part of mime_type)
		aR	aspect_ratio (width/height)
		a3	aspect_ratio3 (3 decimal places after the dot)
		aI	aspect_ratio_inverted (height/width)
		bD	bit_depth

		aC	collection artist (from CDDB_File)
		tT	track title (from CDDB_File)
		cC	collection comment (from CDDB_File)
		cT	track comment (from CDDB_File)
		iC	CDDB id
		iI	CDIndex id

(Multi-char escapes must be inclosed in braces, as in C<%{SML}> or C<%.5{aR}>.

Additional multi-char escapes are interpretated is follows:

=over 4

=item *

Names of ID3v2 frames are replaced by their text values (empty for missing
frames).

=item *

Strings C<n1> and C<n2> are replaced by "pure track number" and
"max track number" (this allows for both formats C<N1> and C<N1/N2> of "track",
the latter meaning track N1 of N2); use C<n0> to pad C<n1> with leading 0
to the width of C<n2> (in absense of n2, to 2).  Likewise for C<m1>, C<m2>
but with disk (media) number instead of track number; use C<mA> to encode
C<m1> as a letter (see L<disk_alphanum()>). 

=item *

Strings C<ID3v1> and C<ID3v2> are replaced by the whole ID3v1/2 tag
(interpolation of C<ID3v2> for an unmodified tag is subject to
C<id3v2_recalculate> configuration variable).  (These may work as
conditionals too, with C<:>.)

=item *

Strings of the form C<FRAM(list,of,languages)[description]'> are
replaced by the first FRAM frame with the descriptor "description" in
the specified comma-separated list of languages.  Instead of a
language (ID3v2 uses lowercase 3-char ISO-639-2 language notations) one can use
a string of the form C<#Number>; e.g., C<#4> means 4th FRAM frame, or
FRAM04.  Empty string for the language means any language.)  Works as
a condition for conditional interpolation too.

Any one of the list of languages and the disription can be omitted;
this means that either the frame FRAM has no language or descriptor
associated, or no restriction should be applied.

Unknown language should be denoted as C<XXX> (in uppercase!).  The language
match is case-insensitive.

=item *

Several descriptors of the form
C<FRAM(list,of,languages)[description]'> discussed above may be
combined together with C<&>; the non-empty expansions are joined
together with C<"; ">.  Example:

  %{TXXX[pre-title]&TIT1&TIT2&TIT3&TXXX[post-title]}


=item *

C<d>I<NUMBER> is replaced by I<NUMBER>-th component of the directory name (with
0 corresponding to the last component).

=item *

C<D>I<NUMBER> is replaced by the directory name with NUMBER components stripped.

=item *

C<U>I<NUMBER> is replaced by I<NUMBER>-th component of the user scratch
array.

=item *

If string starts with C<FNAME:>: if frame FNAME does not exists, the escape
is ignored; otherwise the rest of the string is reinterpreted.

=item *

String starting with C<!FNAME:> are treated similarly with inverted test.

=item *

If string starts with C<FNAME||>: if frame FNAME exists, the part
after C<||> is ignored; otherwise the part before C<||> is ignored,
and the rest is reinterpreted.

=item *

If string starts with C<FNAME|>: if frame FNAME exists, the part
after C<|> is ignored; otherwise the part before C<|> is ignored,
and the rest is reinterpreted as if it started with C<%{>.

=item *

String starting with I<LETTER>C<:> or C<!>I<LETTER>C<:> are treated similarly
to ID3v2 conditionals, but the condition is that the corresponding escape
expands to non-empty string.  Same applies to non-time related 2-char escapes
and user variables.

=item *

Likewise for string starting with I<LETTER>C<|> or I<LETTER>C<||>.

=item *

For strings of the form C<nmP[VALUE]> or C<shP[VALUE]>, I<VALUE> is
interpolated, then normalized or shortened as a personal name
(according to C<translate_person> or C<short_person> configuration
setting).

=item *

C<composer> or C<performer> is replaced by the result of calling the
corresponding method.

=item *

C<frames> is replaced by space-separated list of "long names" of ID3v2
frames (see id3v2_frame_descriptors()).  (To use a different separator,
put it after slash, as in %{frames/, }, where separator is COMMA
SPACE).

=item *

C<_out_frames[QQPRE//QQPOST]> is replaced by a verbose listing of frames.
"simple" frames are output one-per-line (with the value surrounded by
C<QQPRE> and C<QQPOST>); fields of other frames are output one-per-line.
If one omits the leading C<_>, then C<__binary_DATA__> replaces the value
of binary fields.

=item *

C<ID3v2-size>, C<ID3v2-pad>, and C<ID3v2-stripped> are replaced by size of
ID3v2 tag in bytes, the amount of 0-padding at the end of the tag
(not counting one extra 0 byte at the end of tag which may be needed for
unsyncing if the last char is \xFF), and size without padding.  Currently,
for modified ID3v2 tag, what is returned reflect the size on disk (i.e.,
before modification).

=item *

C<ID3v2-modified> is replaced by C<'modified'> if ID3v2 is present and
is modified in memory; otherwise is replaced by an empty string.

=item *

For strings of the form C<I(FLAGS)VALUE>, I<VALUE> is interpolated
with flags in I<FLAGS> (see L<"interpolate_with_flags">).  If FLAGS
does not contain C<i>, VALUE should have C<{}> and C<\> backwacked.

=item *

For strings of the form C<T[FORMAT]>, I<FORMAT> is split on comma, and
the resulting list of formats is used to convert the duration of the
audio to a string using the method format_time().  (E.g.,
C<%{T[=E<gt>m,?H:,{mL}]}> would print duration in (optional) hours and minutes
rounded to the closest minute.)

=back

The default for the fill character is SPACE.  Fill character should preceed
C<-> if both are given.  Example:

   Title: %(/)-12.12t%{TIT3:; TIT3 is %\{TIT3\}}%{!TIT3:. No TIT3 is present}

will result in

   Title: TITLE///////; TIT3 is Op. 16

if title is C<TITLE>, and TIT3 is C<Op. 16>, and

   Title: TITLE///////. No TIT3 is present

if title is C<TITLE>, but TIT3 is not present.

  Fat content: %{COMM(eng,fra,fre,rus,)[FatContent]}

will print the comment field with I<Description> C<FatContent>
prefering the description in English to one in French, Russian, or any
other language (in this order).  (I do not know which one of
terminology/bibliography codes for French is used, so for safety
include both.)

  Composer: %{TCOM|a}

will use the ID3v2 field C<TCOM> if present, otherwise uses C<%a> (this is
similar to

  Composer: %{composer}

but the latter may be subject to (different) normalization, and/or
configuration variables).

Interpolation of ID3v2 frames uses the minimal possible non-ambiguous
backslashing rules: the only backslashes needed are to protect the
innermost closing delimiter (C<]> or C<}>) appearing as a literal
character, or to protect backslashes I<immediately> preceding such
literal, or the closing delimiter.  E.g., the pattern equal to

  %{COMM(eng)[a\b\\c\}\]end\\\]\\\\]: comment `a\b\\c\\\}]end\]\\' present}

checks for the presence of comment with the descriptor C<a\b\\c\}]end\]\\>.
Note that if you want to write this string as a Perl literal, a lot of
extra backslashes may be needed (unless you use C<E<lt>E<lt>'FOO'>
HERE-document).

  %{T[?Hh,?{mL}m,{SML}s]}

for a file of duration 2345.62sec will result in C<39m05.62s>, while

  %{T[?H:,?{mL}:,{SL},?{ML}]}sec

will result in C<39:05.620sec>.

=cut

my %trans = qw(	t	title
		a	artist
		l	album
		y	year
		g	genre
		c	comment
		n	track

		E	filename_extension
		e	filename_extension_nodot
		A	abs_filename_noextension
		B	filename_nodir_noextension
		N	filename_noextension
		f	filename_nodir
		D	dirname
		F	abs_filename

		aC	artist_collection
		tT	title_track
		cC	comment_collection
		cT	comment_track
		iD	cddb_id
		iI	cdindex_id
		n1	track1
		n2	track2
		n0	track0
		mA	disk_alphanum
		m1	disk1
		m2	disk2

		h	height
		w	width
		iT	img_type
		mT	mime_type
		mP	mime_Pretype
		aR	aspect_ratio
		a3	aspect_ratio3
		aI	aspect_ratio_inverted
		bD	bit_depth

		v	mpeg_version
		L	mpeg_layer_roman
		?	is_stereo
		?	is_vbr
		r	bitrate_kbps
		q	frequency_kHz
		Q	frequency_Hz
		?	size_bytes
		S	total_secs_int
		M	total_millisecs_int
		m	total_mins
		mL	leftover_mins
		H	total_hours
		s	leftover_secs
		ML	leftover_msec
		SML	leftover_secs_float
		SL	leftover_secs_trunc
		?	time_mm_ss
		C	is_copyrighted_YN
		p	frames_padded_YN
		o	channel_mode
		u	frames
		?	frame_len
		?	vbr_scale
  );

# Different:	%v is without trailing 0s, %q has fractional part,
#		%e, %E are for the extension,
#		%r is a number instead of 'Variable', %u is one less...
# Missing:
#	%b      Number of corrupt audio frames (integer)
#	%e      Emphasis (string)
#	%E      CRC Error protection (string)
#	%O      Original material flag (string)
#	%G      Musical genre (integer)

my $frame_bra =			# FRAM | FRAM03 | FRAM(lang)[
  qr{\w{4}(?:(?:\d\d)|(?:\([^()]*(?:\([^()]+\)[^()]*)*\))?(?:(\[)|(?=[\}:|&])))}s; # 1 group for begin-descr
# used with offset by 1: 2: fill, 3: same, 4: $left, 5..6 width, 7: key
my $pat_rx = qr/^%(?:(?:\((.)\)|([^-.1-9%a-zA-Z]))?(-)?(\d+))?(?:\.(\d+))?([talgcynfFeEABDNvLrqQSmsCpouMHwh{%])/s;
# XXXX Partially repeated below, search for `talgc'??? vLrqQSmsCpouMH miss???

my $longer_f = qr(a[3CRI]|tT|c[TC]|i[DIT]|n[012]|m[A12TP]|bD);
# (a[CR]|tT|c[TC]|[mMS]L|SML|i[DIT]|n[012]|m[A12T]|bD)
#  a[CR]|tT|c[TC]|i[DIT]|n[012]|m[A12T]|bD

# $upto TRUE: parse the part including $upto char
# Very restricted backslashitis: only $upto and \ before $upto-or-end
# $upto defined but FALSE: interpolate only one %-escape.
# Anyway: $_[1] is modified to remove interpolated part.
sub _interpolate ($$;$$) {
    # goto &interpolate_flags if @_ == 3;
    my ($self, undef, $upto, $skip) = @_; # pattern is modified, so is $_[1]
    $self->get_tags();
    my $res = "";
    my $ids;
    die "upto=`$upto' not supported" if $upto and $upto ne ']' and $upto ne'}';
    die "upto=`$upto' not supported with skip"
      if $upto and not defined $upto and $skip;
    my $cnt = ($upto or not defined $upto) ? -1 : 1; # upto eq '': 1 escape

    while ($cnt-- and ($upto	# undef and '' use the same code
		       ? ($upto eq ']'
			  ? $_[1] =~ s/^((?:[^%\\\]]|(?:\\\\)*\\\]|\\+[^\\\]]|\\\\)+)|$pat_rx//so
			  : $_[1] =~ s/^((?:[^%\\\}]|(?:\\\\)*\\\}|\\+[^\\\}]|\\\\)+)|$pat_rx//so)
		       : $_[1] =~ s/^([^%]+)|$pat_rx//so)) {
        if (defined $1) {
	  my $str = $1;
	  if ($upto and $upto eq ']') {
	    $str =~ s<((?:\\\\)*)(?:\\(?=\])|(?!.))>< '\\' x (length($1)/2) >ges;
	  } elsif ($upto and $upto eq '}') {
	    $str =~ s<((?:\\\\)*)(?:\\(?=\})|(?!.))>< '\\' x (length($1)/2) >ges;
	  }
	  $res .= $str, next;
	}
	my ($fill, $left, $minwidth, $maxwidth, $what)
	    = ((defined $2 ? $2 : $3), $4, $5, $6, $7);
	next if $skip and $what ne '{';
	my $str;
	if ($what eq '{' and $_[1] =~ s/^([dD])(\d+)}//) {	# Directory
	    next if $skip;
	    if ($1 eq 'd') {
		$str = $self->dir_component($2);
	    } else {
		$str = $self->dirname($2);
	    }
	} elsif ($what eq '{' and $_[1] =~ s/^U(\d+)}//) {	# User data
	    next if $skip;
	    $str = $self->get_user($1);
	} elsif ($what eq '{' and $_[1] =~ s/^($longer_f|[mMS]L|SML)}//o) {
	  # CDDB, IDs, or leftover times
	    next if $skip;
	    my $meth = $trans{$1};
	    $str = $self->$meth();
	} elsif ($what eq '{' and # $frame_bra has 1 group, No. 5
		 # 2-char fields as above, except for [mMS]L|SML (XXX: vLrqQSmsCpouMH ???)
		 $_[1] =~ s/^(!)?(([talgcynfFeEABDNvLrqQSmsCpouMHwh]|ID3v[12]|ID3v2-modified|$longer_f|U\d+)(:|\|\|?)|$frame_bra)//o) {
	    # Alternation with simple/complicated stuff
	    my ($neg, $id, $simple, $delim) = ($1, $2, $3, $4);
	    if ($delim) {	# Not a frame id...
	      $id = $simple;
	    } else {		# Frame: maybe trailed by :, |, ||, maybe not
	      $id .= ($self->_interpolate($_[1], ']', $skip) . ']') if $5;
	      $_[1] =~ s/^(:|\|\|?)// and $delim = $1;
	      unless ($delim) {
		die "Can't parse negated conditional: I see `$_[1]'" if $neg;
		my $nonesuch = 0;
		unless ($self->{ID3v2} or $neg) {
		  die "No ID3v2 present"
		    if $self->get_config('id3v2_missing_fatal');
		  $nonesuch = 1;
		}
		if ($_[1] =~ s/^}//) { # frame with optional (lang)/[descr]
		  next if $skip or $nonesuch;
		  $str = $self->select_id3v2_frame_by_descr($id);
		  #$str = $str->{_Data} if $str and ref $str and exists $str->{_Data};
		} elsif ($_[1] =~ /^&/o) {
		  # join of frames with optional (language)/[descriptor]
		  my @id = $id;
		  while ($_[1] =~ s/^&($frame_bra)//o) {
		    $id = $1;
		    $id .= ($self->_interpolate($_[1], ']', $skip) . ']') if $2;
		    next if $skip or $nonesuch;
		    push @id, $id;
		  }
		  die "Can't parse &-list; I see `$_[1]'" unless $_[1] =~ s/^}//;
		  next if $skip or $nonesuch;
		  my @out;
		  for my $in (@id) {
		    $in = $self->select_id3v2_frame_by_descr($in);
		    #$in = $in->{_Data} if $in and ref $in and exists $in->{_Data};
		    push @out, $in if defined $in and length $in;
		  }
		  $str = join '; ', @out;
		} else {
		  die "unknown frame terminator; I see `$_[1]'";
		}
	      }
	    }
	    if ($delim) {	# Conditional
	      # $self->_interpolate($_[1], $upto, $skip), next if $skip;
	      my $alt = ($delim ne ':') && $delim; # FALSE or $delim
	      die "Negation and alternation incompatible in interpolation"
		if $alt and $neg;
	      my $have;
	      if ($simple and (2 >= length $simple or $simple =~ /^U/)) {
		my $s = (1 == length $simple ? $simple : "{$simple}");
		$str = $self->interpolate("%$s");
		$have = length($str);
	      } elsif (($simple || '') eq 'ID3v2-modified') {	# may be undef
		$have = ${ $self->{ID3v2} || {} }{modified} || '';
	      } elsif ($simple) { # ID3v2 or ID3v1
		die "ID3v2 or ID3v1 as conditionals incompatible with $alt"
		  if $alt;
		$have = !! $self->{$simple}; # Make logical
	      } else {
		$have = $self->have_id3v2_frame_by_descr($id);
	      }
	      my $skipping = $skip || (not $alt and $1 ? $have : !$have);
	      my $s;
	      if ($alt and $alt ne '||') { # Need to prepend %
		if ($_[1] =~ s/^([^\\])}//) { # One-char escape
		  $s = $self->interpolate("%$1") unless $skipping;
		} else {	# Understood with {}; prepend %{
		  $_[1] =~ s/^/%\{/ or die;
		  $s = $self->_interpolate($_[1], '', $skipping);
		}
	      } else {
		$s = $self->_interpolate($_[1], '}', $skipping);
	      }
	      next if $skipping;
	      $str = $self->select_id3v2_frame_by_descr($id)
		if $alt and $have and not $simple;
	      $str = $s unless $have and $alt;
	      $str = $str->{_Data}
		if $str and ref $str and exists $str->{_Data};
	    }
	} elsif ($what eq '{' and $_[1] =~ s/^ID3v1}//) {
	    next if $skip;
	    $str = $self->{ID3v1}->as_bin if $self->{ID3v1};
	} elsif ($what eq '{'
		 and $_[1] =~ s/^(sh|nm)P\[//s) {
	    # (Short) personal name
	    $what = $1;
	    $str = $self->_interpolate($_[1], ']', $skip);
	    $_[1] =~ s/^\}// or die "Can't find end of ${what}P escape; I see `$_[1]'";
	    next if $skip;
	    my $meth = ($what eq 'sh' ? 'shorten_person' : 'normalize_person');
	    $str = $self->$meth($str);
	} elsif ($what eq '{' and $_[1] =~ s/^I\((\w+)\)//s) {
	    # Interpolate
	    my $flags = $1;
	    if ($flags =~ s/i//) {
	      $str = $self->_interpolate($_[1], '}', $skip);
	    } else {
	      $_[1] =~ s/^((?:[^\\\}]|(?:\\\\)*\\\}|\\+[^\\\}]|\\\\)*)\}//s
	      #		$_[1] =~ s/^((?:\\.|[^{}\\])*)}//
		or die "Can't find non-interpolated argument in `$_[1]'";
	      next if $skip;
	      # ($str = $1) =~ s/\\([\\{}])/$1/g;
	      ($str = $1) =~ s<((?:\\\\)*)(?:\\(?=\})|(?!.))>< '\\' x (length($1)/2) >ges;
	    }
	    next if $skip;
	    ($str) = $self->interpolate_with_flags($str, $flags);
	} elsif ($what eq '{' and $_[1] =~ s/^T\[([^\[\]]*)\]\}//s) { # time
	    next if $skip;
	    $str = $self->format_time(undef, split /,/, $1);
	} elsif ($what eq '{') {	#id3v2=whole, composer/performer/frames
	    unless ($self->{ID3v2} or $skip) {
		die "No ID3v2 present"
		  if $self->get_config('id3v2_missing_fatal');
		$_[1] =~ s/^[^\}]*}//; # XXXX No error checking here...
		next;
	    }
	    if ($_[1] =~ s/ID3v2}//) { # Whole tag
		if (not $skip and $self->{ID3v2}) {
		  if ($self->get_config('id3v2_recalculate')) {
		    $str = $self->{ID3v2}->as_bin;
		  } else {
		    $str = $self->{ID3v2}->as_bin_raw;
		  }
		}
	    } elsif ($_[1] =~ s/^(composer|performer)}//) {
	      $str = $self->$1() unless $skip;
	    } elsif ($_[1] =~ s,^frames(?:/(.*?))?},,) {
	      my $sep = (defined $1 ? $1 : ' ');
	      $str = join $sep, $self->id3v2_frame_descriptors() unless $skip;
	    } elsif ($_[1] =~ s,^(_)?out_frames\[(.*?)//(.*?)\]},,) {
	      my($bin, $pre, $post) = ($1, $2, $3);
	      my $v2 = $self->{ID3v2};
		# $fr_sep, $fn_sep, $pre,$post,$fsep,$pre_mult,$val_sep		# length "Picture Type" = 12
	      $str = ($v2 ? $v2->__frames_as_printable("\n", "\t==>\n  ", $pre,	# Tune tabbing for length=5..12 (_Data)
						       $post, "\n  ", "", " \t=\t", $bin) : '') unless $skip;
	    } elsif ($_[1] =~ s,^ID3v2-size},,) {
	      my $v2 = $self->{ID3v2};
	      $str = ($v2 ? 10 + $v2->{buggy_padding_size} + $v2->{tagsize} : 0)
		unless $skip;
	    } elsif ($_[1] =~ s,^ID3v2-pad},,) {
	      my $v2 = $self->{ID3v2};
	      $v2->get_frame_ids() if $v2 and not exists $v2->{frameIDs};
	      $str = ($v2 ? $v2->{padding} : 0) unless $skip;
	    } elsif ($_[1] =~ s,^ID3v2-stripped},,) {
	      my $v2 = $self->{ID3v2};
	      $v2->get_frame_ids() if $v2 and not exists $v2->{frameIDs};
	      $str = ($v2 ? 10 + $v2->{buggy_padding_size} + $v2->{tagsize} - $v2->{padding} : 0) unless $skip;
	    } elsif ($_[1] =~ s,^ID3v2-modified},,) {
	      my $v2 = $self->{ID3v2};
	      $str = ($v2 and $v2->{modified}) || '' unless $skip;
	    } else {
	      die "unknown escape; I see `$_[1]'";
	    }
	} elsif ($what eq '%') {
	    $str = '%';
	} else {
	    my $meth = $trans{$what};
	    $str = $self->$meth();
	}
	$str = '' unless defined $str;
	if (defined $maxwidth and length $str > $maxwidth) {
	  if ($str =~ /^(?:\+|(\-))?(\d*)(\.\d*)?$/) {
	    if (length($1 || '') + length $2 <= $maxwidth) {
	      my $w = $maxwidth - length $2 - length($1 || '');
	      $w-- if $w;	# Take into account decimal point...
	      $str = sprintf '%.*f', $w, $str
	    } else {		# Might be a long integer benefiting from %g
	      my($w, $s0) = ($maxwidth, $str);
	      while ($w >= 1) {
		$str = sprintf '%.*g', $w, $s0;
		$str =~ s/(^|(?<=[-+]))0+|(?<=e)\+//gi; # 1e+07 to 1e7
		last if length $str <= $maxwidth;
		$w--
	      }
	      $str = $s0 if length $str > length $s0; # 12 vs 1e1
	      $str = substr $str, 0, $maxwidth;	# 1e as a truncation of 1234 is better than 12...
	    }
	  } else {
	    $str = substr $str, 0, $maxwidth;
	  }
	}
	if (defined $minwidth) {
	  $fill = ' ' unless defined $fill;
	  if ($left) {
	    $str .= $fill x ($minwidth - length $str);
	  } else {
	    $str = $fill x ($minwidth - length $str) . $str;
	  }
	}
	$res .= $str;
    }
    if (defined $upto) {
      not $upto or
	($upto eq ']' ? $_[1] =~ s/^\]// : $_[1] =~ s/^\}//)
	  or die "Can't find final delimiter `$upto': I see `$_[1]'";
    } else {
      die "Can't parse `$_[1]' during interpolation" if length $_[1];
    }
    return $res;
}

sub interpolate ($$) {
  my ($self, $pattern) = @_;	# local copy; $pattern is modified
  $self->_interpolate($pattern);
}


=item interpolate_with_flags

  @results = $mp3->interpolate_with_flags($text, $flags);

Processes $text according to directives in the string $flags; $flags is
split into separate flag characters; the meanings (and order of application) of
flags are

   i			interpolate via $mp3->interpolate
   f			interpret (the result) as filename, read from file
   F			if file does not exist, it is not an error
   B			read is performed in binary mode (otherwise
				in text mode, modified per
				'decode_encoding_files' configuration variable)
   l			split result per 'parse_split' configuration variable
   n			as l, using the track-number-th element (1-based)
				in the result
   I			interpolate (again) via $mp3->interpolate
   b			unless present, remove leading and trailing whitespace

With C<l>, may produce multiple results.  May be accessed via
interpolation of C<%{I(flags)text}>.

=cut

sub interpolate_with_flags ($$$) {
    my ($self, $data, $flags) = @_;

    $data = $self->interpolate($data) if $flags =~ /i/;
    if ($flags =~ /f/) {
	local *F;
	my $e;
	unless (open F, "< $data") {
	  return if $flags =~ /F/;
	  die "Can't open file `$data' for parsing: $!";
	}
	if ($flags =~ /B/) {
	  binmode F;
	} else {
	  my $e;
	  if ($e = $self->get_config('decode_encoding_files') and $e->[0]) {
	    eval "binmode F, ':encoding($e->[0])'"; # old binmode won't compile...
	  }
	}

	local $/;
	my $d = <F>;
	CORE::close F or die "Can't close file `$data' for parsing: $!";
	$data = $d;
    }
    my @data = $data;
    if ($flags =~ /[ln]/) {
	my $p = $self->get_config('parse_split')->[0];
	@data = split $p, $data, -1;
    }
    if ($flags =~ /n/) {
	my $track = $self->track1 or return;
	@data = $data[$track - 1];
    }
    for my $d (@data) {
	$d = $self->interpolate($d) if $flags =~ /I/;
	unless ($flags =~ /b/) {
	    $d =~ s/^\s+//;
	    $d =~ s/\s+$//;
	}
    }
    @data;
}

=item parse_rex($pattern, $string)

Parse $string according to the regular expression $pattern with
C<%>-escapes C<%%, %a, %t, %l, %y, %g, %c, %n, %e, %E>.  The meaning
of escapes is the same as for method L<"interpolate">(); but they are
used not for I<expansion>, but for I<matching> a part of $string
suitable to be a value for these fields.  Returns false on failure, a
hash reference with parsed fields otherwise.

Some more escapes are supported: C<%=a, %=t, %=l, %=y, %=g, %=c, %=n, %=e,
%=E, %=A, %=B, %=D, %=f, %=F, %=N, %={WHATEVER}> I<match>
substrings which are I<current> values of artist/title/etc (C<%=n> also
matches leading 0s; actual file-name matches ignore the difference
between C</> and C<\>, between one and multiple consequent dots (if
configuration variable C<parse_filename_merge_dots> is true (default))
and are case-insensitive if configuration variable
C<parse_filename_ignore_case> is true (default); moreover, C<%n>,
C<%y>, C<%=n>, C<%=y> will not match if the string-to-match is
adjacent to a digit).

The escapes C<%{UE<lt>numberE<gt>}> and escapes of the forms
C<%{ABCD}>, C<%{ABCDE<lt>numberE<gt>}> match any string; the
corresponding hash key in the result hash is what is inside braces;
here C<ABCD> is a 4-letter word possibly followed by 2-digit number
(as in names of ID3v2 tags), or what can be put in
C<'%{FRAM(lang,list)[description]}'>.

  $res = $mp3->parse_rex( qr<^%a - %t\.\w{1,4}$>,
			  $mp3->filename_nodir ) or die;
  $author = $res->{author};

2-digit numbers, or I<number1/number2> with number1,2 up to 999 are
allowed for the track number (the leading 0 is stripped); 4-digit
years in the range 1000..2999 are allowed for year.  Alternatively, if
option year_is_timestamp is TRUE (default), year may be a range of
timestamps in the format understood by ID3v2 method year() (see
L<MP3::Tag::ID3v2/"year">).

Currently the regular expressions with capturing parens are not supported.

=item parse_rex_prepare($pattern)

Returns a data structure which later can be used by parse_rex_match().
These two are equivalent:

  $mp3->parse_rex($pattern, $data);
  $mp3->parse_rex_match($mp3->parse_rex_prepare($pattern), $data);

This call constitutes the "slow part" of the parse_rex() call; it makes sense to
factor out this step if the parse_rex() with the same $pattern is called
against multiple $data.

=item parse_rex_match($prepared, $data)

Matches $data against a data structure returned by parse_rex_prepare().
These two are equivalent:

  $mp3->parse_rex($pattern, $data);
  $mp3->parse_rex_match($mp3->parse_rex_prepare($pattern), $data);

=cut

sub _rex_protect_filename {
    my ($self, $filename, $what) = (shift, quotemeta shift, shift);
    $filename =~ s,\\[\\/],[\\\\/],g;	# \ and / are interchangeable + backslashitis
    if ($self->get_config('parse_filename_merge_dots')->[0]) {
	# HPFS doesn't distinguish x..y and x.y
	$filename =~ s(\\\.+)(\\.+)g;
	$filename =~ s($)(\\.*) if $what =~ /[ABN]/;
    }
    my $case = $self->get_config('parse_filename_ignore_case')->[0];
    return $filename unless $case;
    return "(?i:$filename)";
}

sub _parse_rex_anything ($$) {
    my $c = shift->get_config('parse_minmatch');
    my $min = $c->[0];
    if ($min and $min ne '1') {
	my $field = shift;
	$min = grep $_ eq $field, @$c;
    }
    return $min ? '(.*?)' : '(.*)';
}

sub __pure_track_rex ($) {
  my $t = shift()->track;
  $t =~ s/^0+//;
  $t =~ s,^(.*?)(/.*),\Q$1\E(?:\Q$2\E)?,;
  $t
}

sub _parse_rex_microinterpolate {	# $self->idem($code, $groups, $ecount)
    my ($self, $code, $groups) = (shift, shift, shift);
    return '%' if $code eq '%';
    # In these two, allow setting to '', and to 123/789 too...
    push(@$groups, $code), return '((?<!\d)\d{1,3}(?:/\d{1,3})?(?!\d)|\A\Z)' if $code eq 'n';
    (push @$groups, $code), return '((?<!\d)[12]\d{3}(?:(?:--|[-:/T\0,])\d(?:|\d|\d\d\d))*(?!\d)|\A\Z)'
	if $code eq 'y' and ($self->get_config('year_is_timestamp'))->[0];
    (push @$groups, $code), return '((?<!\d)[12]\d{3}(?!\d)|\A\Z)'
	if $code eq 'y';
    # Filename parts ABDfFN and vLrqQSmsCpouMH not settable...
    (push @$groups, $code), return $self->_parse_rex_anything($code)
	if $code =~ /^[talgc]$/;
    $_[0]++, return $self->_rex_protect_filename($self->interpolate("%$1"), $1)
	if $code =~ /^=([ABDfFN]|{d\d+})$/;
    $_[0]++, return quotemeta($self->interpolate("%$1"))
	if $code =~ /^=([talgceEwhvLrqQSmsCpouMH]|{.*})$/;
    $_[0]++, return '(?<!\d)0*' . $self->__pure_track_rex . '(?!\d)'
	if $code eq '=n';
    $_[0]++, return '(?<!\d)' . quotemeta($self->year) . '(?!\d)'
	if $code eq '=y';
    (push @$groups, $1), return $self->_parse_rex_anything()
	if $code =~ /^{(U\d+|\w{4}(\d\d+|(?:\([^\)]*\))?(?:\[.*\])?)?)}$/s;
    # What remains is extension
    my $e = $self->get_config('extension')->[0];
    (push @$groups, $code), return "($e)" if $code eq 'E';
    (push @$groups, $code), return "(?<=(?=(?:$e)\$)\\.)(.*)" if $code eq 'e';
    # Check whether '=' was omitted, as in %f
    $code =~ /^=/ or
      eval {my ($a, $b); $self->_parse_rex_microinterpolate("=$code", $a, $b)}
	and die "escape `%$code' can't be parsed; did you forget to put `='?";
    die "unknown escape `%$code'";
}

sub parse_rex_prepare {
    my ($self, $pattern) = @_;
    my ($codes, $exact, $p) = ([], 0, '');
    my $o = $pattern;
    # (=? is correct! Group 4 is inside $frame_bra
    while ($pattern =~ s<^([^%]+)|%(=?{(?:($frame_bra)|[^}]+})|=?.)><>so) {
      if (defined $1) {
	$p .= $1;
      } else {
	my $group = $2;
	# description begins
	$group .= ($self->_interpolate($pattern, ']') . ']') if $4;
	if ($3) {
	  $pattern =~ s/^}// or die "Can't find end of frame name, I see `$p'";
	  $group .= '}';
	}
	$p .= $self->_parse_rex_microinterpolate($group, $codes, $exact);
      }
    }
    die "Can't parse pattern, I see `$pattern'" if length $pattern;
    #$pattern =~ s<%(=?{(?:[^\\{}]|\\[\\{}])*}|{U\d+}|=?.)> # (=? is correct!
    #		 ( $self->_parse_rex_microinterpolate($1, $codes, $exact) )seg;
    my @tags = map { length == 1 ? $trans{$_} : $_ } @$codes;
    return [$o, $p, \@tags, $exact];
}

sub parse_rex_match {	# pattern = [Original, Interpolated, Fields, NumExact]
    my ($self, $pattern, $data) = @_;
    return unless @{$pattern->[2]} or $pattern->[3];
    my @vals = ($data =~ /$pattern->[1]()/s) or return;	# At least 1 group
    my $cv = @vals - 1;
    die "Unsupported %-regular expression `$pattern->[0]' (catching parens? Got $cv vals) (converted to `$pattern->[1]')"
	unless $cv == @{$pattern->[2]};
    my ($c, %h) = 0;
    for my $k ( @{$pattern->[2]} ) {
	$h{$k} ||= [];
	push @{ $h{$k} }, $vals[$c++];	# Support multiple occurences
    }
    my $j = $self->get_config('parse_join')->[0];
    for $c (keys %h) {
	$h{$c} = join $j, grep length, @{ $h{$c} };
    }
    $h{track} =~ s/^0+(?=\d)// if exists $h{track};
    return \%h;
}

sub parse_rex {
    my ($self, $pattern, $data) = @_;
    $self->parse_rex_match($self->parse_rex_prepare($pattern), $data);
}

=item parse($pattern, $string)

Parse $string according to the string $pattern with C<%>-escapes C<%%,
%a, %t, %l, %y, %g, %c, %n, %e, %E>.  The meaning of escapes is the
same as for L<"interpolate">. See L<"parse_rex($pattern, $string)">
for more details.  Returns false on failure, a hash reference with
parsed fields otherwise.

  $res = $mp3->parse("%a - %t.mp3", $mp3->filename_nodir) or die;
  $author = $res->{author};

2-digit numbers are allowed for the track number; 4-digit years in the range
1000..2999 are allowed for year.

=item parse_prepare($pattern)

Returns a data structure which later can be used by parse_rex_match().
This is a counterpart of parse_rex_prepare() used with non-regular-expression
patterns.  These two are equivalent:

  $mp3->parse($pattern, $data);
  $mp3->parse_rex_match($mp3->parse_prepare($pattern), $data);

This call constitutes the "slow part" of the parse() call; it makes sense to
factor out this step if the parse() with the same $pattern is called
against multiple $data.

=cut

#my %unquote = ('\\%' => '%', '\\%\\=' => '%=');
sub __unquote ($) { (my $k = shift) =~ s/\\(\W)/$1/g; $k }

sub parse_prepare {
    my ($self, $pattern) = @_;
    $pattern = "^\Q$pattern\E\$";
    # unquote %. and %=. and %={WHATEVER} and %{WHATEVER}
    $pattern =~ s<(\\%(?:\\=)?(\w|\\{(?:\w|\\[^\w\\{}]|\\\\\\[\\{}])*\\}|\\\W))>
		 ( __unquote($1) )ge;
    # $pattern =~ s/(\\%(?:\\=)?)(\w|\\(\W))/$unquote{$1}$+/g;
    return $self->parse_rex_prepare($pattern);
}

sub parse {
    my ($self, $pattern, $data) = @_;
    $self->parse_rex_match($self->parse_prepare($pattern), $data);
}

=item filename()

=item abs_filename()

=item filename_nodir()

=item filename_noextension()

=item filename_nodir_noextension()

=item abs_filename_noextension()

=item dirname([$strip_levels])

=item filename_extension()

=item filename_extension_nodot()

=item dir_component([$level])

  $filename = $mp3->filename();
  $abs_filename = $mp3->abs_filename();
  $filename_nodir = $mp3->filename_nodir();
  $abs_dirname = $mp3->dirname();
  $abs_dirname = $mp3->dirname(0);
  $abs_parentdir = $mp3->dirname(1);
  $last_dir_component = $mp3->dir_component(0);

Return the name of the audio file: either as given to the new() method, or
absolute, or directory-less, or originally given without extension, or
directory-less without extension, or
absolute without extension, or the directory part of the fullname only, or
filename extension (with dot included, or not).

The extension is calculated using the config() value C<extension>.

The dirname() method takes an optional argument: the number of directory
components to strip; the C<dir_component($level)> method returns one
component of the directory (to get the last use 0 as $level; this is the
default if no $level is specified).

The configuration option C<decode_encoding_filename> can be used to
specify the encoding of the filename; all these functions would use
filename decoded from this encoding.

=cut

sub from_filesystem ($$) {
  my ($self, $f) = @_;
  my $e = $self->get_config('decode_encoding_filename');
  return $f unless $e and $e->[0];
  require Encode;
  Encode::decode($e->[0], $f);
}

sub filename {
  my $self = shift;
  $self->from_filesystem($self->{ofilename});
}

sub abs_filename {
  my $self = shift;
  $self->from_filesystem($self->{abs_filename});
}

sub filename_noextension {
    my $self = shift;
    my $f = $self->filename;
    my $ext_re = $self->get_config('extension')->[0];
    $f =~ s/$ext_re//;
    return $f;
}

sub filename_nodir {
    require File::Basename;
    return scalar File::Basename::fileparse(shift->filename, "");
}

sub dirname {
    require File::Basename;
    my ($self, $l) = (shift, shift);
    my $p = $l ? $self->dirname($l - 1) : $self->abs_filename;
    return File::Basename::dirname($p);
}

sub dir_component {
    require File::Basename;
    my ($self, $l) = (shift, shift);
    return scalar File::Basename::fileparse($self->dirname($l), "");
}

sub filename_extension {
    my $self = shift;
    my $f = $self->filename_nodir;
    my $ext_re = $self->get_config('extension')->[0];
    $f =~ /($ext_re)/ or return '';
    return $1;
}

sub filename_nodir_noextension {
    my $self = shift;
    my $f = $self->filename_nodir;
    my $ext_re = $self->get_config('extension')->[0];
    $f =~ s/$ext_re//;
    return $f;
}

sub abs_filename_noextension {
    my $self = shift;
    my $f = $self->abs_filename;
    my $ext_re = $self->get_config('extension')->[0];
    $f =~ s/$ext_re//;
    return $f;
}

sub filename_extension_nodot {
    my $self = shift;
    my $e = $self->filename_extension;
    $e =~ s/^\.//;
    return $e;
}

=item mpeg_version()

=item mpeg_layer()

=item mpeg_layer_roman()

=item is_stereo()

=item is_vbr()

=item bitrate_kbps()

=item frequency_Hz()

=item frequency_kHz()

=item size_bytes()

=item total_secs()

=item total_secs_int()

=item total_secs_trunc()

=item total_millisecs_int()

=item total_mins()

=item leftover_mins()

=item leftover_secs()

=item leftover_secs_float()

=item leftover_secs_trunc()

=item leftover_msec()

=item time_mm_ss()

=item is_copyrighted()

=item is_copyrighted_YN()

=item frames_padded()

=item frames_padded_YN()

=item channel_mode_int()

=item frames()

=item frame_len()

=item vbr_scale()

These methods return the information about the contents of the MP3
file.  If this information is not cached in ID3v2 tags (not
implemented yet), using these methods requires that the module
L<MP3::Info|MP3::Info> is installed.  Since these calls are
redirectoed to the module L<MP3::Info|MP3::Info>, the returned info is
subject to the same restrictions as the method get_mp3info() of this
module; in particular, the information about the frame number and
frame length is only approximate.

vbr_scale() is from the VBR header; total_secs() is not necessarily an
integer, but total_secs_int() and total_secs_trunc() are (first is
rounded, second truncated); time_mm_ss() has format C<MM:SS>; the
C<*_YN> flavors return the value as a string Yes or No;
mpeg_layer_roman() returns the value as a roman numeral;
channel_mode() takes values in C<'stereo', 'joint stereo', 'dual
channel', 'mono'>.

=cut

my %mp3info = qw(
  mpeg_version		VERSION
  mpeg_layer		LAYER
  is_stereo		STEREO
  is_vbr		VBR
  bitrate_kbps		BITRATE
  frequency_kHz		FREQUENCY
  size_bytes		SIZE
  is_copyrighted	COPYRIGHT
  frames_padded		PADDING
  channel_mode_int	MODE
  frames		FRAMES
  frame_len		FRAME_LENGTH
  vbr_scale		VBR_SCALE
  total_secs_fetch	SECS
);

# Obsoleted:
#  total_mins		MM
#  time_mm_ss		TIME
#  leftover_secs		SS
#  leftover_msec		MS

for my $elt (keys %mp3info) {
  no strict 'refs';
  my $k = $mp3info{$elt};
  *$elt = sub (;$) {
    # $MP3::Info::try_harder = 1;	# Bug: loops infinitely if no frames
    my $self = shift;
    my $info = $self->{mp3info};
    unless ($info) {
      require MP3::Info;
      $info = MP3::Info::get_mp3info($self->abs_filename);
      die "Didn't get valid data from MP3::Info for `".($self->abs_filename)."': $@"
        unless defined $info;
    }
    $info->{$k}
  }
}

sub frequency_Hz ($) {
  1000 * (shift->frequency_kHz);
}

sub mpeg_layer_roman	{ eval { 'I' x (shift->mpeg_layer) } || '' }
sub total_millisecs_int_fetch	{ int (0.5 + 1000 * shift->duration_secs) }
sub frames_padded_YN	{ eval {shift->frames_padded() ? 'Yes' : 'No' } || '' }
sub is_copyrighted_YN	{ eval {shift->is_copyrighted() ? 'Yes' : 'No' } || '' }

sub total_millisecs_int {
  my $self = shift;
  my $ms = $self->{ms};
  return $ms if defined $ms;
  (undef, $ms) = $self->get_id3v2_frames('TLEN');
  $ms = $self->total_millisecs_int_fetch() unless defined $ms;
  $self->{ms} = $ms;
  return $ms;
}
sub total_secs_int	{ int (0.5 + 0.001 * shift->total_millisecs_int) }
sub total_secs		{ 0.001 * shift->total_millisecs_int }
sub total_secs_trunc	{ int (0.001 * (0.5 + shift->total_millisecs_int)) }
sub total_mins		{ int (0.001/60 * (0.5 + shift->total_millisecs_int)) }
sub leftover_mins	{ shift->total_mins() % 60 }
sub total_hours		{ int (0.001/60/60 * (0.5 + shift->total_millisecs_int)) }
sub leftover_secs	{ shift->total_secs_int() % 60 }
sub leftover_secs_trunc	{ shift->total_secs_trunc() % 60 }
sub leftover_msec	{ shift->total_millisecs_int % 1000 }
sub leftover_secs_float	{ shift->total_millisecs_int % 60000 / 1000 }
sub time_mm_ss {		# Borrowed from MP3::Info
  my $self = shift;
  sprintf "%.2d:%.2d", $self->total_mins, $self->leftover_secs;
}

sub duration_secs {	# Tricky: in which order to query MP3::Info and ExifTool?
  my $self = shift;
  my $d = $self->{duration};
  return $d if defined $d;	# Cached value
  return $self->{duration} = $self->total_secs_fetch	# Have MP3::Info or a chance to work
    if $self->{mp3info} or $self->{filename} =~ /\.mp[23]$/i;
  my $r = $self->_duration;	# Next: try ExifTool
  $r = $self->total_secs_fetch unless $r; # Try MP3::Info anyway
  return $r;
}

=item format_time

  $output = $mp3->format_time(67456.123, @format);

formats time according to @format, which should be a list of format
descriptors.  Each format descriptor is either a simple letter, or a
string in braces appropriate to be put after C<%> in an interpolated
string.  A format descriptor can be followed by a literal string to be
put as a suffix, and can be preceded by a question mark, which says
that this part of format should be printed only if needed.

Leftover minutes, seconds are formated 0-padded to width 2 if they are
preceded by more coarse units.  Similarly, leftover milliseconds are
printed with leading dot, and 0-padded to width 3.

Two examples of useful C<@format>s are

  qw(?H: ?{mL}: {SML})
  qw(?Hh ?{mL}m {SL} ?{ML})

Both will print hours, minutes, and milliseconds only if needed.  The
second one will use 3 digit-format after a point, the first one will
not print the trailing 0s of milliseconds.  The first one uses C<:> as
separator of hours and minutes, the second one will use C<h m>.

Optionally, the first element of the array may be of the form
C<=E<gt>U>, here C<U> is one of C<h m s>.  In this case, duration is
rounded to closest hours, min or second before processing.  (E.g.,
1.7sec would print as C<1> with C<@format>s above, but would print as
C<2> if rounded to seconds.)

=cut

my %Unit = qw( h 3600 m 60 s 1 );

sub format_time {
  my ($self, $time) = (shift, shift);
  $self = $self->new_fake() unless ref $self;
  local $self->{ms} =  $self->{ms}; # Make modifiable
  local $self->{ms} = int($time * 1000 + 0.5) if defined $time;
  my ($out, %have, $c) = '';
  for my $f (@_) {
    $have{$+}++ if $f =~ /^\??({([^{}]+)}|.)/;
  }
  for my $f (@_) {
    if (!$c++ and $f =~ /^=>(\w)$/) {
      my $u = $Unit{$1} or die "Unexpected unit of time for rounding: `$1'";
      $time = $self->total_secs unless defined $time;
      $time = $u * int($time/$u + 0.5);
      $self->{ms} = 1000 * $time;
      next;
    }
    my $ff = $f;		# Modifiable
    my $opt = ($ff =~ s/^\?//);
    $ff =~ s/^({[^{}]+}|\w)// or die "unexpected time format: <<$f>>";
    my ($what, $format) = ($1, '');
    if ($opt) {
      if ($what eq 'H') {
	$time = $self->total_secs unless defined $time;
	$opt = int($time / 3600) || !(grep $have{$_}, qw(m mL s S SL SML));
      } elsif ($what eq 'm' or $what eq '{mL}') {
	$time = $self->total_secs unless defined $time;
	$opt = int($time / 60) || !(grep $have{$_}, qw(s S SL SML));
      } elsif ($what eq '{ML}') {
	$opt = ($time != int $time);
      } else {
	$opt = 1;
	#die "Do not know how to treat optional `$what'";
      }
      $what =~ /^(?:{(.*)}|(.))/ or die;
      (delete $have{$+}), next unless $opt;
    }
    $format = '02'
      if (($what eq 's' or $what eq '{SL}') and (grep $have{$_}, qw(H m mL)))
	or $what eq '{mL}' and $have{H};
    $what = "%$format$what";
    $what = ".%03{ML}"
      if $what eq '%{ML}' and grep $have{$_}, qw(H m mL s S SL);
    if ($what eq '%{SML}' and grep $have{$_}, qw(H m mL)) { # manual padding
      my $res = $self->interpolate($what);
      $res = "0$res" unless $res =~ /^\d\d/;
      $out .= "$res$ff";
    } else {
      $out .= $self->interpolate($what) . $ff;
    }
  }
  $out;
}

my @channel_modes = ('stereo', 'joint stereo', 'dual channel', 'mono');
sub channel_mode	{ $channel_modes[shift->channel_mode_int] }

=item can_write()

checks permission to write per the configuration variable C<is_writable>.

=item can_write_or_die($mess)

as can_write(), but die()s on non-writable files with meaningful error message
($mess is prepended to the message).

=item die_cant_write($mess)

die() with the same message as can_write_or_die().

=item writable_by_extension()

Checks that extension is (case-insensitively) in the list given by
configuration variable C<writable_extensions>.

=cut

sub can_write ($) {
    my $self = shift;
    my @wr = @{ $self->get_config('is_writable') };	# Make copy
    return $wr[0] if @wr == 1 and not $wr[0] =~ /\D/;
    my $meth = shift @wr;
    $self->$meth(@wr);
}

sub writable_by_extension ($) {
    my $self = shift;
    my $wr = $self->get_config('writable_extensions');	# Make copy
    $self->extension_is(@$wr);
}

sub die_cant_write ($$) {
    my($self, $what) = (shift, shift);
    die $what, $self->interpolate("File %F is not writable per `is_writable' confuration variable, current value is `"),
		join(', ', @{$self->get_config('is_writable')}), "'";
}

sub can_write_or_die ($$) {
    my($self, $what) = (shift, shift);
    my $wr = $self->can_write;
    return $wr if $wr;
    $self->die_cant_write($what);
}

=item update_tags( [ $data,  [ $force2 ]] )

  $mp3 = MP3::Tag->new($filename);
  $mp3->update_tags();			# Fetches the info, and updates tags

  $mp3->update_tags({});		# Updates tags if needed/changed

  $mp3->update_tags({title => 'This is not a song'});	# Updates tags

This method updates ID3v1 and ID3v2 tags (the latter only if in-memory copy
contains any data, or $data does not fit ID3v1 restrictions, or $force2
argument is given)
with the the information about title, artist, album, year, comment, track,
genre from the hash reference $data.  The format of $data is the same as
one returned from autoinfo() (with or without the optional argument 'from').
The fields which are marked as coming from ID3v1 or ID3v2 tags are not updated
when written to the same tag.

If $data is not defined or missing, C<autoinfo('from')> is called to obtain
the data.  Returns the object reference itself to simplify chaining of method
calls.

This is probably the simplest way to set data in the tags: populate
$data and call this method - no further tinkering with subtags is
needed.

=cut

sub update_tags {
    my ($mp3, $data, $force2, $wr2) = (shift, shift, shift);

    $mp3->get_tags;
    $data = $mp3->autoinfo('from') unless defined $data;

#    $mp3->new_tag("ID3v1") unless $wr1 = exists $mp3->{ID3v1};
    unless (exists $mp3->{ID3v1}) {
	$mp3->can_write_or_die('update_tags() doing ID3v1: ');
	$wr2 = 1;
	$mp3->new_tag("ID3v1");
    }
    my $elt;
    for $elt (qw/title artist album year comment track genre/) {
	my $d = $data->{$elt};
	next unless defined $d;
	$d = [$d, ''] unless ref $d;
        $mp3->{ID3v1}->$elt( $d->[0] ) if $d->[1] ne 'ID3v1';
    }				# Skip what is already there...
    $mp3->{ID3v1}->write_tag;

    my $do_length
      = (defined $mp3->{ms}) ? ($mp3->get_config('update_length'))->[0] : 0;

    return $mp3
      if not $force2 and $mp3->{ID3v1}->fits_tag($data)
	and not exists $mp3->{ID3v2} and $do_length < 2;

#    $mp3->new_tag("ID3v2") unless exists $mp3->{ID3v2};
    unless (exists $mp3->{ID3v2}) {
	if (defined $wr2) {
	    $mp3->die_cant_write('update_tags() doing ID3v2: ') unless $wr2;
	} else {
	    $mp3->can_write_or_die('update_tags() doing ID3v2: ');
	}
	$mp3->new_tag("ID3v2");
    }
    for $elt (qw/title artist album year comment track genre/) {
	my $d = $data->{$elt};
	next unless defined $d;
	$d = [$d, ''] unless ref $d;
        $mp3->{ID3v2}->$elt( $d->[0] ) if $d->[1] ne 'ID3v2';
    }				# Skip what is already there...
    # $mp3->{ID3v2}->comment($data->{comment}->[0]);

    $mp3->set_id3v2_frame('TLEN', $mp3->{ms})
      if $do_length and not $mp3->have_id3v2_frame('TLEN');
    $mp3->{ID3v2}->write_tag;
    return $mp3;
}

sub _massage_genres ($;$) {   # Thanks to neil verplank for the prototype
    require MP3::Tag::ID3v1;
    my($data, $how) = (shift, shift);
    my $firstnum = (($how || 0) eq 'num');
    my $prefer_num = (($how || 0) eq 'prefer_num');
    my (%seen, @genres);	# find all genres in incoming data
    $data = $data->[0] if ref $data;
    # clean and split line on both null and parentheses
    $data =~ s/\s+/ /g;
    $data =~ s/\s*\0[\0\s]*/\0/g;
    $data =~ s/^[\s\0]+//;
    $data =~ s/[\s\0]+$//;
    my @data = split m<\0|\s+/\s+>, $data;
    @data = split /\( ( \d+ | rx | cr ) \)/xi, $data[0] if @data == 1;

    # review array, produce a clean, ordered list of unique genres for output
    foreach my $genre (@data) {
        next if $genre eq "";  # (12)(13) ==> in front, and between

        # convert text to number to eliminate collisions, and produce consistent output
        if ($genre =~ /\D/) {{	# Not a pure number
            # return id number
            my $genre_num = MP3::Tag::ID3v1::genres($genre); 
            # 255 is "non-standard text" in ID3v1; pass the rest through
            last if $genre_num eq '255' or $genre_num eq '';
	    return $genre_num if $firstnum;
	    $genre = $genre_num, last if $prefer_num;
	    $genre_num = MP3::Tag::ID3v1::genres($genre_num);
            last unless defined $genre_num;
            $genre = $genre_num;
        }}	# Now converted to a number - if possible
        unless ($prefer_num or $genre =~ /\D/) {{ # Here $genre is a number
	    my $genre_str = MP3::Tag::ID3v1::genres($genre) or last;
	    return $genre if $firstnum;
            $genre = $genre_str;
        }}
        # 2.4 defines these conversions
        $genre = "Remix" if lc $genre eq "rx";
        $genre = "Cover" if lc $genre eq "cr";
        $genre = "($genre)" if length $genre and not $genre =~ /\D/;	# Only digits
        push @genres, $genre unless $seen{$genre}++;
    }
    return if $firstnum;
    @genres;
}

=item extension_is

  $mp3->extension_is(@EXT_LIST)

returns TRUE if the extension of the filename coincides (case-insensitive)
with one of the elements of the list.

=cut

sub extension_is ($@) {
  my ($self) = (shift);
  my $ext = lc($self->filename_extension_nodot());
  return 1 if grep $ext eq lc, @_;
  return;
}

sub DESTROY {
    my $self=shift;
    if (exists $self->{filename} and defined $self->{filename}) {
	$self->{filename}->close;
    }
}

sub parse_cfg_line ($$$) {
  my ($self, $line, $data) = (shift,shift,shift);
  return if $line =~ /^\s*(#|$)/;
  die "Unrecognized configuration file line: <<<$line>>>"
    unless $line =~ /^\s*(\w+)\s*=\s*(.*?)\s*$/;
  push @{$data->{$1}}, $2;
}

=item C<parse_cfg( [$filename] )>

Reads configuration information from the specified file (defaults to
the value of configuration variable C<local_cfg_file>, which is
C<~>-substituted).  Empty lines and lines starting with C<#> are ignored.
The remaining lines should have format C<varname=value>; leading
and trailing whitespace is stripped; there may be several lines with the same
C<varname>; this sets list-valued variables.

=back

=cut

sub parse_cfg ($;$) {
  my ($self, $file) = (shift,shift);
  $file = ($self->get_config('local_cfg_file'))->[0] unless defined $file;
  return unless defined $file;
  $file =~ s,^~(?=[/\\]),$ENV{HOME}, if $ENV{HOME};
  return unless -e $file;
  open F, "< $file" or die "Can't open `$file' for read: $!";
  my $data = {};
  while (defined (my $l = <F>)) {
    $self->parse_cfg_line($l, $data);
  }
  CORE::close F or die "Can't close `$file' for read: $!";
  for my $k (keys %$data) {
    $self->config($k, @{$data->{$k}});
  }
}

my @parents = qw(User Site Vendor);

@MP3::Tag::User::ISA = qw( MP3::Tag::Site MP3::Tag::Vendor
			   MP3::Tag::Implemenation ); # Make overridable
@MP3::Tag::Site::ISA = qw( MP3::Tag::Vendor MP3::Tag::Implemenation );
@MP3::Tag::Vendor::ISA = qw( MP3::Tag::Implemenation );

sub load_parents {
  my $par;
  while ($par = shift @parents) {
    return 1 if eval "require MP3::Tag::$par; 1"
  }
  return;
}
load_parents() unless $ENV{MP3TAG_SKIP_LOCAL};
MP3::Tag->parse_cfg() unless $ENV{MP3TAG_SKIP_LOCAL};

1;

=pod

=head1 ENVIRONMENT

Some defaults for the operation of this module (and/or scripts distributed
with this module) are set from
environment.  Assumed encodings (0 or encoding name): for read access:

  MP3TAG_DECODE_V1_DEFAULT		MP3TAG_DECODE_V2_DEFAULT
  MP3TAG_DECODE_FILENAME_DEFAULT	MP3TAG_DECODE_FILES_DEFAULT
  MP3TAG_DECODE_INF_DEFAULT		MP3TAG_DECODE_CDDB_FILE_DEFAULT
  MP3TAG_DECODE_CUE_DEFAULT

for write access:

  MP3TAG_ENCODE_V1_DEFAULT		MP3TAG_ENCODE_FILES_DEFAULT

(if not set, default to corresponding C<DECODE> options).

Defaults for the above:

  MP3TAG_DECODE_DEFAULT			MP3TAG_ENCODE_DEFAULT

(if the second one is not set, the value of the first one is used).
Value 0 for more specific variable will cancel the effect of the less
specific variables.

These variables set default configuration settings for C<MP3::Tag>;
the values are read during the load time of the module.  After load,
one can use config()/get_config() methods to change/access these
settings.  See C<encode_encoding_*> and C<encode_decoding_*> in
documentation of L<config|config> method.  (Note that C<FILES> variant
govern file read/written in non-binary mode by L<MP3/ParseData> module,
as well as reading of control files of some scripts using this module, such as
L<typeset_audio_dir>.)

=over

=item B<EXAMPLE>

Assume that locally present CDDB files and F<.inf> files
are in encoding C<cp1251> (this is not supported by "standard", but since
the standard supports only a handful of languages, this is widely used anyway),
and that one wants C<ID3v1> fields to be in the same encoding, but C<ID3v2>
have an honest (Unicode, if needed) encoding.  Then set

   MP3TAG_DECODE_INF_DEFAULT=cp1251
   MP3TAG_DECODE_CDDB_FILE_DEFAULT=cp1251
   MP3TAG_DECODE_V1_DEFAULT=cp1251

Since C<MP3TAG_DECODE_V1_DEFAULT> implies C<MP3TAG_ENCODE_V1_DEFAULT>,
you will get the desired effect both for read and write of MP3 tags.

=back

Additionally, the following (unsupported) variables are currently
recognized by ID3v2 code:

  MP3TAG_DECODE_UNICODE			MP3TAG_DECODE_UTF8

MP3TAG_DECODE_UNICODE (default 1) enables decoding; the target of
decoding is determined by MP3TAG_DECODE_UTF8: if 0, decoded values are
byte-encoded UTF-8 (every Perl character contains a byte of UTF-8
encoded string); otherwise (default) it is a native Perl Unicode
string.

If C<MP3TAG_SKIP_LOCAL> is true, local customization files are not loaded.

=head1 CUSTOMIZATION

Many aspects of operation of this module are subject to certain subtle
choices.  A lot of effort went into making these choices customizable,
by setting global or per-object configuration variables.

A certain degree of customization of global configuration variables is
available via the environment variables.  Moreover, at startup the local
customization file F<~/.mp3tagprc> is read, and defaults are set accordingly.

In addition, to make customization as flexible as possible, I<ALL> aspects
of operation of C<MP3::Tag> are subject to local override.  Three customization
modules

  MP3::Tag::User	MP3::Tag::Site		MP3::Tag::Vendor

are attempted to be loaded if present.  Only the first module (of
those present) is loaded directly; if sequential load is desirable,
the first thing a customization module should do is to call

  MP3::Tag->load_parents()

method.

The customization modules have an opportunity to change global
configuration variables on load.  To allow more flexibility, they may
override any method defined in C<MP3::Tag>; as usual, the overriden
method may be called using C<SUPER> modifier (see L<perlobj/"Method
invocation">).

E.g., it is recommended to make a local customization file with

  eval 'require Normalize::Text::Music_Fields';
  for my $elt ( qw( title track artist album comment year genre
		    title_track artist_collection person ) ) {
    no strict 'refs';
    MP3::Tag->config("translate_$elt", \&{"Normalize::Text::Music_Fields::normalize_$elt"})
      if defined &{"Normalize::Text::Music_Fields::normalize_$elt"};
  }
  MP3::Tag->config("short_person", \&Normalize::Text::Music_Fields::short_person)
      if defined &Normalize::Text::Music_Fields::short_person;

and install the (supplied, in the F<examples/modules>) module
L<Normalize::Text::Music_Fields> which enables normalization of person
names (to a long or a short form), and of music piece names to
canonical forms.

To simplify debugging of local customization, it may be switched off
completely by setting MP3TAG_SKIP_LOCAL to TRUE (in environment).

For example, putting

  id3v23_unsync	= 0

into F<~/.mp3tagprc> will produce broken ID3v2 tags (but those required
by ITunes).

=head1 EXAMPLE SCRIPTS

Some example scripts come with this module (either installed, or in directory
F<examples> in the distribution); they either use this module, or
provide data understood by this module:

=over

=item mp3info2

perform command line manipulation of audio tags (and more!);

=item audio_rename

rename audio files according to associated tags (and more!);

=item typeset_mp3_dir

write LaTeX files suitable for CD covers and normal-size sheet
descriptions of hierarchy of audio files;

=item mp3_total_time

Calculate total duration of audio files;

=item eat_wav_mp3_header

remove WAV headers from MP3 files in WAV containers.

=item fulltoc_2fake_cddb

converts a CD's "full TOC" to a "fake" CDDB file (header only).  Create
this file with something like

  readcd -fulltoc dev=0,1,0 -f=audio_cd >& nul

run similar to

  fulltoc_2fake_cddb < audio_cd.toc | cddb2cddb > cddb.out

=item dir_mp3_2fake_cddb

tries to convert a directory of MP3 files to a "fake" CDDB file (header only);
assumes that files are a rip from a CD, and that alphabetical sort gives
the track order (works only heuristically, since quantization of duration
of MP3 files and of CD tracks is so different).

Run similar to

  dir_mp3_2fake_cddb | cddb2cddb > cddb.out


=item inf_2fake_cddb

tries to convert a directory of F<.inf> files to a "fake" CDDB file (header
only).  (Still heuristic, since it can't guess the length of the leader.)

Run similar to

  inf_2fake_cddb | cddb2cddb > cddb.out

=item cddb2cddb

Reads a (header of) CDDB file from STDIN, outputs (on STDOUT) the current
version of the database record.  Can be used to update a file, and/or to
convert a fake CDDB file to a real one.

=back

(Last four do not use these modules!)

Some more examples:

  # Convert from one (non-standard-conforming!) encoding to another
  perl -MMP3::Tag -MEncode -wle '
    my @fields = qw(artist album title comment);
    for my $f (@ARGV) {
      print $f;
      my $t = MP3::Tag->new($f) or die;
      $t->update_tags(
	{ map { $_ => encode "cp1251", decode "koi8-r", $t->$_() }, @fields }
      );
    }' list_of_audio_files

=head1 Problems with ID3 format

The largest problem with ID3 format is that the first versions of these
format were absolutely broken (underspecified).  It I<looks> like the newer
versions of this format resolved most of these problems; however, in reality
they did not (due to unspecified backward compatibility, and
grandfathering considerations).

What are the problems with C<ID3v1>?  First, one of the fields was C<artist>,
which does not make any sense.  In particular, different people/publishers
would put there performer(s), composer, author of text/lyrics, or a combination
of these.  The second problem is that the only allowed encoding was
C<iso-8859-1>; since most of languages of the world can't be expressed
in this encoding, this restriction was completely ignored, thus the
encoding is essentially "unknown".

Newer versions of C<ID3> allow specification of encodings; however,
since there is no way to specify that the encoding is "unknown", when a
tag is automatically upgraded from C<ID3v1>, it is most probably assumed to be
in the "standard" C<iso-8859-1> encoding.  Thus impossibility to
distinguish "unknown, assumed C<iso-8859-1>" from "known to be C<iso-8859-1>"
in C<ID3v2>, essentially, makes any encoding specified in the tag "unknown"
(or, at least, "untrusted").  (Since the upgrade [or a chain of upgrades]
from the C<ID3v1> tag to the C<ID3v2> tag can result in any encoding of
the "supposedly C<iso-8859-1>" tag, one cannot trust the content of
C<ID3v2> tag even if it stored as Unicode strings.)

This is why this module provides what some may consider only lukewarm support
for encoding field in ID3v2 tags: if done fully automatic, it can allow
instant propagation of wrong information; and this propagation is in a form
which is quite hard to undo (but still possible to do with suitable settings
to this module; see L<mp3info2/"Examples on dealing with broken encodings">).

Likewise, the same happens with the C<artist> field in C<ID3v1>.  Since there
is no way to specify just "artist, type unknown" in C<ID3v2> tags, when
C<ID3v1> tag is automatically upgraded to C<ID3v2>, the content would most
probably be put in the "main performer", C<TPE1>, tag.  As a result, the
content of C<TPE1> tag is also "untrusted" - it may contain, e.g., the composer.

In my opinion, a different field should be used for "known to be
principal performer"; for example, the method performer() (and the
script F<mp3info2> shipped with this module) uses C<%{TXXX[TPE1]}> in
preference to C<%{TPE1}>.

For example, interpolate C<%{TXXX[TPE1]|TPE1}> or C<%{TXXX[TPE1]|a}> -
this will use the frame C<TXXX> with identifier C<TPE1> if present, if not,
it will use the frame C<TPE1> (the first example), or will try to get I<artist>
by other means (including C<TPE1> frame) (the second example).

=head1 FILES

There are many files with special meaning to this module and its dependent
modules.

=over 4

=item F<*.inf>

Files with extension F<.inf> and the same basename as the audio file are
read by module C<MP3::Tag::Inf>, and the extracted data is merged into the
information flow according to configuration variable C<autoinfo>.

It is assumed that these files are compatible in format to the files written
by the program F<cdda2wav>.

=item F<audio.cddb> F<cddb.out> F<cddb.in>

in the same directory as the audio file are read by module
C<MP3::Tag::CDDB_File>, and the extracted data is merged into the
information flow according to configuration variable C<autoinfo>.

(In fact, the list may be customized by configuration variable C<cddb_files>.)

=item F<audio_cd.toc>

in the same directory as the audio file may be read by the method
id3v2_frames_autofill() (should be called explicitly) to fill the C<TXXX[MCDI-fulltoc]>
frame.  Depends on contents of configuration variable C<id3v2_frames_autofill>.

=item F<~/.mp3tagprc>

By default, this file is read on startup (may be customized by overriding
the method parse_cfg()).  By default, the name of the file is in the
configuration variable C<local_cfg_file>.

=back

=head1 SEE ALSO

L<MP3::Tag::ID3v1>, L<MP3::Tag::ID3v2>, L<MP3::Tag::File>,
L<MP3::Tag::ParseData>, L<MP3::Tag::Inf>, L<MP3::Tag::CDDB_File>,
L<MP3::Tag::Cue>, L<mp3info2>,
L<typeset_audio_dir>.

=head1 COPYRIGHT

Copyright (c) 2000-2008 Thomas Geffert, Ilya Zakharevich.  All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=cut

