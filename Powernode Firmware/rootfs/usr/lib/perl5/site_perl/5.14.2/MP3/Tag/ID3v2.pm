package MP3::Tag::ID3v2;

# Copyright (c) 2000-2004 Thomas Geffert.  All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the Artistic License, distributed
# with Perl.

use strict;
use File::Basename;
# use Compress::Zlib;

use vars qw /%format %long_names %res_inp @supported_majors %v2names_to_v3
	     $VERSION @ISA %field_map %field_map_back %is_small_int
	     %back_splt %embedded_Descr
	    /;

$VERSION = "1.12";
@ISA = 'MP3::Tag::__hasparent';

my $trustencoding = $ENV{MP3TAG_DECODE_UNICODE};
$trustencoding = 1 unless defined $trustencoding;

my $decode_utf8 = $ENV{MP3TAG_DECODE_UTF8};
$decode_utf8 = 1 unless defined $decode_utf8;
my $encode_utf8 = $decode_utf8;

=pod

=head1 NAME

MP3::Tag::ID3v2 - Read / Write ID3v2.x.y tags from mp3 audio files

=head1 SYNOPSIS

MP3::Tag::ID3v2 supports
  * Reading of ID3v2.2.0 and ID3v2.3.0 tags (some ID3v2.4.0 frames too)
  * Writing of ID3v2.3.0 tags

MP3::Tag::ID3v2 is designed to be called from the MP3::Tag module.  If
you want to make calls from user code, please consider using
highest-level wrapper code in MP3::Tag, such as update_tags() and
select_id3v2_frame_by_descr().

Low-level creation code:

  use MP3::Tag;
  $mp3 = MP3::Tag->new($filename);

  # read an existing tag
  $mp3->get_tags();
  $id3v2 = $mp3->{ID3v2} if exists $mp3->{ID3v2};

  # or create a new tag
  $id3v2 = $mp3->new_tag("ID3v2");

See L<MP3::Tag|according documentation> for information on the above used functions.

* Reading a tag, very low-level:

  $frameIDs_hash = $id3v2->get_frame_ids('truename');

  foreach my $frame (keys %$frameIDs_hash) {
      my ($name, @info) = $id3v2->get_frames($frame);
      for my $info (@info) {
	  if (ref $info) {
	      print "$name ($frame):\n";
	      while(my ($key,$val)=each %$info) {
		  print " * $key => $val\n";
             }
          } else {
	      print "$name: $info\n";
          }
      }
  }

* Adding / Changing / Removing a frame in memory (higher-level)

  $t = $id3v2->frame_select("TIT2", undef, undef); # Very flexible

  $c = $id3v2->frame_select_by_descr("COMM(fre,fra,eng,#0)[]");
  $t = $id3v2->frame_select_by_descr("TIT2");
       $id3v2->frame_select_by_descr("TIT2", "MyT"); # Set/Change
       $id3v2->frame_select_by_descr("RBUF", $n1, $n2, $n3); # Set/Change
       $id3v2->frame_select_by_descr("RBUF", "$n1;$n2;$n3"); # Set/Change
       $id3v2->frame_select_by_descr("TIT2", undef); # Remove

* Adding / Changing / Removing a frame in memory (low-level)

  $id3v2->add_frame("TIT2", "Title of the audio");
  $id3v2->change_frame("TALB","Greatest Album");
  $id3v2->remove_frame("TLAN");

* Output the modified-in-memory version of the tag:

  $id3v2->write_tag();

* Removing the whole tag from the file

  $id3v2->remove_tag();

* Get information about supported frames

  %tags = $id3v2->supported_frames();
  while (($fname, $longname) = each %tags) {
      print "$fname $longname: ", 
            join(", ", @{$id3v2->what_data($fname)}), "\n";
  }

=head1 AUTHOR

Thomas Geffert, thg@users.sourceforge.net
Ilya Zakharevich, ilyaz@cpan.org

=head1 DESCRIPTION

=over 4

=item get_frame_ids()

  $frameIDs = $tag->get_frame_ids;
  $frameIDs = $tag->get_frame_ids('truename');

  [old name: getFrameIDs() . The old name is still available, but you should use the new name]

get_frame_ids loops through all frames, which exist in the tag. It
returns a hash reference with a list of all available Frame IDs. The
keys of the returned hash are 4-character-codes (short names), the
internal names of the frames, the according value is the english
(long) name of the frame.

You can use this list to iterate over all frames to get their data, or to
check if a specific frame is included in the tag.

If there are multiple occurences of a frame in one tag, the first frame is
returned with its normal short name, following frames of this type get a
'01', '02', '03', ... appended to this name.  These names can then
used with C<get_frame> to get the information of these frames.  These
fake frames are not returned if C<'truename'> argument is set; one
can still use C<get_frames()> to extract the info for all of the frames with
the given short name.

=cut

###### structure of a tag frame
#
# major=> Identifies format of frame, normally set to major version of the whole
#         tag, but many ID3v2.2 frames are converted automatically to ID3v2.3 frames
# flags=> Frame flags, depend on major version
# data => Data of frame, including gid
# gid  => group id, if any (created by get_frame())
#

sub un_syncsafe_4bytes ($) {
    my ($rawsize,$size) = (shift, 0);
    foreach my $b (unpack("C4", $rawsize)) {
	$size = ($size << 7) + $b;
    }
    return $size;
}

sub get_frame_ids {
        my $self = shift;		# Tag
        my $basic = shift;

	# frame headers format for the different majors
	my $headersize = (0,0,6,10,10)[$self->{major}];
	my $headerformat=("","","a3a3","a4Nn","a4a4n")[$self->{major}];

	if (exists $self->{frameIDs}) {
	        return unless defined wantarray;
		my %return;
		foreach (keys %{$self->{frames}}) {
		    next if $basic and length > 4;   # ignore frames with 01 etc. at end
		    $return{$_}=$long_names{substr($_,0,4)};
		}
		return \%return;
	}

	my $pos = $self->{frame_start};
#	if ($self->{flags}->{extheader}) {
#		warn "get_frame_ids: possible wrong IDs because of unsupported extended header\n";
#	}
	my $buf;
	while ($pos + $headersize < $self->{data_size}) {
		$buf = substr ($self->{tag_data}, $pos, $headersize);
		my ($ID, $size, $flags) = unpack($headerformat, $buf);
		# tag size is handled differently for all majors
		if ($self->{major} == 2) {
			# flags don't exist in id3v2.2
			$flags=0;
			my $rawsize=$size;
			$size=0;
			foreach (unpack("C3", $rawsize)) {
				$size = ($size << 8) + $_;
			}
		} elsif ($self->{major} == 4) {
		    $size = un_syncsafe_4bytes $size;
		} elsif ($self->{major}==3 and $size>255) {
			# Size>255 means at least 2 bytes are used for size.
			# Some programs use (incorectly) for the frame size
			# the format of the tag size (snchsafe). Trying do detect that here
			if ($pos + $headersize + $size > $self->{data_size} ||
			    !exists $long_names{substr ($self->{tag_data}, $pos+$size,4)}) {
				# wrong size or last frame
				my $fsize = un_syncsafe_4bytes substr $buf, 4, 4;
				if ($pos + 20 + $fsize < $self->{data_size} &&
				    exists $long_names{substr ($self->{tag_data}, $pos+10+$fsize,4)}) {
					warn "Probably wrong size format found in frame $ID. Trying to correct it\n";
					#probably false size format detected, using corrected size
					$size = $fsize;
				}
			}
		}

		if ($ID !~ "\000\000\000") {
		        my $major = $self->{major};
			if ($major == 2) {
				# most frame IDs can be converted directly to id3v2.3 IDs
				 if (exists  $v2names_to_v3{$ID}) {
				     # frame is direct convertable to major 3
				     $ID = $v2names_to_v3{$ID};
				     $major=3;
				 }
			}
			if (exists $self->{frames}->{$ID}) {
			        ++$self->{extra_frames}->{$ID};
			        $ID .= '01';
				while (exists $self->{frames}->{$ID}) {
					$ID++;
				}
			}

			$self->{frames}->{$ID} = {flags=>$self->check_flags($flags),
						  major=>$major,
						  data=>substr($self->{tag_data}, $pos+$headersize, $size)};
			$pos += $size+$headersize;
		} else { # Padding reached, cut tag data here
			last;
		}
	}
	$self->{endpos} = $pos;
	# Since tag_data is de-synced, this doesn't count the forced final "\0"
	$self->{padding} = length($self->{tag_data}) - $pos;
	# tag is seperated into frames, tagdata not more needed
	$self->{tag_data}="";

	$self->{frameIDs} =1;
	my %return;
	foreach (keys %{$self->{frames}}) {
	        next if $basic and length > 4;   # ignore frames with 01 etc. at end
		$return{$_}=$long_names{substr($_,0,4)};
	}
	return \%return;
}

*getFrameIDs = \&get_frame_ids;

=pod

=item get_frame()

  ($info, $name, @rest) = $tag->get_frame($ID);
  ($info, $name, @rest) = $tag->get_frame($ID, 'raw');

  [old name: getFrame() . The old name is still available, but you should use the new name]

get_frame gets the contents of a specific frame, which must be specified by the
4-character-ID (aka short name). You can use C<get_frame_ids> to get the IDs of
the tag, or use IDs which you hope to find in the tag. If the ID is not found, 
C<get_frame> returns empty list, so $info and $name become undefined.

Otherwise it extracts the contents of the frame. Frames in ID3v2 tags can be
very small, or complex and huge. That is the reason, that C<get_frame> returns
the frame data in two ways, depending on the tag.

If it is a simple tag, with only one piece of data, these data is returned
directly as ($info, $name), where $info is the text string, and $name is the
long (english) name of the frame.

If the frame consist of different pieces of data, $info is a hash reference, 
$name is again the long name of the frame.

The hash, to which $info points, contains key/value pairs, where the key is 
always the name of the data, and the value is the data itself.

If the name starts with a underscore (as eg '_code'), the data is probably
binary data and not printable. If the name starts without an underscore,
it should be a text string and printable.

If the second parameter is given as C<'raw'>, the whole frame data is returned,
but not the frame header.  If the second parameter is C<'intact'>, no mangling
of embedded C<"\0"> and trailing spaces is performed.  If the second parameter
is C<'hash'>, then, additionally, the result is always in the hash format;
likewise, if it is C<'array'>, the result is an array reference (with C<key
=E<gt> value> pairs same as with C<'hash'>, but ordered as in the frame).
If it is C<'array_nokey'>, only the "value" parts are returned (in particular,
the result is suitable to give to add_frame(), change_frame()); in addition,
if it is C<'array_nodecode'>, then keys are not returned, and the setting of
C<decode_encoding_v2> is ignored.  (The "return array" flavors don't massage
the fields for better consumption by humans, so the fields should be in format
suitable for frame_add().)

If the data was stored compressed, it is
uncompressed before it is returned (even in raw mode). Then $info contains a string
with all data (which might be binary), and $name the long frame name.

See also L<MP3::Tag::ID3v2_Data> for a list of all supported frames, and
some other explanations of the returned data structure.

If more than one frame with name $ID is present, @rest contains $info
fields for all consequent frames with the same name.  Note that after
removal of frames there may be holes in the list of frame names (as in
C<FRAM FRAM01 FRAM02>) in the case when multiple frames of the given
type were present; the removed frames are returned as C<undef>.

! Encrypted frames are not supported yet !

! Some frames are not supported yet, but the most common ones are supported !

=cut

sub get_frame {
    my ($self, $fname, $raw) = @_;
    $self->get_frame_ids() unless exists $self->{frameIDs};
    my ($e, @extra) = 0;				# More frames follow?
    $e = $self->{extra_frames}->{$fname} || 0
            if wantarray and $self->{extra_frames} and length $fname == 4;
    @extra = map scalar $self->get_frame((sprintf "%s%02d", $fname, $_), $raw),
            1..$e;
    $e = grep defined, @extra;
    my $frame = $self->{frames}->{$fname};
    return unless defined $frame or $e;
    $fname = substr ($fname, 0, 4);
    return (undef, $long_names{$fname}, @extra) unless defined $frame;
    my $start_offset=0;
    if ($frame->{flags}->{encryption}) {
	warn "Frame $fname: encryption not supported yet\n" ;
	return;
    }

    my $result = $frame->{data};

#   Some frame format flags indicate that additional information fields
#   are added to the frame. This information is added after the frame
#   header and before the frame data in the same order as the flags that
#   indicates them. I.e. the four bytes of decompressed size will precede
#   the encryption method byte. These additions affects the 'frame size'
#   field, but are not subject to encryption or compression.
    if ($frame->{flags}->{groupid}) {
	$frame->{gid} = substring $result, 0, 1;
	$result = substring $result, 1;
    }

    if ($frame->{flags}->{compression}) {
	my $usize=unpack("N", $result);
	require Compress::Zlib;
	$result = Compress::Zlib::uncompress(substr ($result, 4));
	warn "$fname: Wrong size of uncompressed data\n" if $usize=!length($result);
    }

    if (($raw ||= 0) eq 'raw') {
      return ($result, $long_names{$fname}, @extra) if wantarray;
      return $result;
    }

    my $format = get_format($fname);
    if (defined $format) {
      my($as_arr, $nodecode);
      $as_arr = 2   if $raw eq 'array';
      $as_arr = 1   if $raw eq 'array_nokey' or $raw eq 'array_nodecode';
      $nodecode = 1 if $raw eq 'array_nodecode';
      $format = [map +{%$_}, @$format], $format->[-1]{data} = 1
	if $raw eq 'intact' or $raw eq 'hash' or $as_arr;
      $result = extract_data($self, $result, $format, $nodecode, $as_arr);
      unless ($as_arr or $raw eq 'hash') {
	my $k = scalar keys %$result;
	$k-- if exists $result->{encoding};
	if ($k == 1) {
	  if (exists $result->{Text}) {
	    $result = $result->{Text};
	  } elsif (exists $result->{URL}) {
	    $result = $result->{URL};
	  } elsif ($fname =~ /^MCDI/) {		# Per ID3v2_Data.pod
	    $result = $result->{_Data};
	  }	# In fact, no other known frame has one element
	}
      }
    }
    if (wantarray) {
      return ($result, $long_names{$fname}, @extra);
    } else {
      return $result;
    }
}

*getFrame= \&get_frame;

=item get_frame_descr()

  $long_name = $self->get_frame_descr($fname);

returns a "long name" for the frame (such as C<COMM(eng)[lyricist birthdate]>),
appropriate for interpolation, or for frame_select_by_descr().

=item get_frame_descriptors()

  @long_names = $self->get_frame_descriptors();

return "long names" for the frames in the tag (see C<get_frame_descr>).

=cut

sub get_frame_descr {
    my ($self, $fname)=@_;
    (undef, my $frame) = $self->get_frames($fname); # Ignore the rest
    return unless defined $frame;
    return $fname unless ref $frame;
    my $k = scalar keys %$frame;
    if ($k == 5 and substr($fname, 0, 4) eq 'APIC') {
      return $fname unless
	$frame->{'MIME type'} eq $self->_Data_to_MIME($frame->{_Data});
      delete $frame->{'MIME type'};
      $k--;
      $frame->{Language} = delete $frame->{'Picture Type'};
    }
    return $fname unless $k <= 4; # encoding, Language, Description + 1
    $k-- if exists $frame->{encoding};
    return $fname unless $k <= 3;
    my $l = delete $frame->{Language};
    $k-- if defined $l;
    return $fname unless $k <= 2;
    my $d = delete $frame->{Description};
    $k-- if defined $d;
    return $fname unless $k <= 1;
    $fname =~ s/^(\w{4})\d{2}/$1/;
    $l = "($l)" if defined $l;
    $d = "[$d]" if defined $d;
    $l ||= '';
    $d ||= '';
    return "$fname$l$d";
}

sub get_frame_descriptors {
  my $self = shift;
  my $h = $self->get_frame_ids();
  map $self->get_frame_descr($_), sort keys %$h;
}

# I'm not yet ready to freeze these APIs
sub __frame_as_printable {
  my ($self,$descr,$pre,$post,$fsep,$pre_mult,$val_sep, $bin) = (shift, shift, shift, shift, shift, shift, shift, shift);
  my $val = $self->frame_select_by_descr($descr);
  # Simple binary frames:
  my $l = length $val;
  return '__binary_DATA__ [len='.length($val).']'
    if not $bin and not ref $val and $descr =~ /^(MCDI|APIC)/;
  return "$pre$val$post" unless ref $val;
  my $format = get_format(substr $descr, 0, 4);
  my %optnl = map(($_->{name},$_->{optional}), @$format);
  my @keys = map $_->{name}, @$format;	# In order...
  s/^_(?=encoding$)// for @keys;	# Reverse mangling by extract_data()...
  my %keys = map(($_,1), @keys);
  my @ekeys = grep !exists $keys{$_}, keys %$val;	# Just in case...
  my @miss = grep(!exists $val->{$_}, @keys);
  @miss = map "$_".($optnl{$_} ? ' [optional]' : ''), @miss;
  my $miss = @miss ? "${fsep}missing fields: ".(join ', ', @miss)."." : '';
  @keys = ( grep(exists $val->{$_}, @keys), sort @ekeys ); # grep: just in case
  my %ekeys = map(($_,''), @keys);
  @ekeys{@ekeys} = ('?') x @ekeys;

  return $pre_mult . (join $fsep,
	 map "$ekeys{$_}".sprintf('%-14s',$_)."$val_sep$pre$val->{$_}$post", @keys) . $miss if $bin;
  $pre_mult . (join $fsep, map "$ekeys{$_}".sprintf('%-14s',$_)."$val_sep"
    . ( $_ =~ /^_(?!encoding)/ ? '__binary_DATA__ [len='.length($val->{$_}).']'
	: "$pre$val->{$_}$post" ), @keys) . $miss;
}

sub __f_long_name ($$) {
  my ($self,$fr) = (shift, shift);
  (my $short = $fr) =~ s/^(\w{4})\d{2,}/$1/;
  $long_names{$short} || '???';
}

sub __frames_as_printable {
  my ($self,$fr_sep,$fn_sep) = (shift, shift, shift);
  my $h = $self->get_frame_ids();
  join $fr_sep, map sprintf('%-40s', 
			    $self->get_frame_descr($_)
			      . "  (" . $self->__f_long_name($_) . ")")
		    . $fn_sep . $self->__frame_as_printable($_,@_), sort keys %$h;
}


=pod

=item get_frame_option()

  $options = get_frame_option($ID);

  Option is a hash reference, the hash contains all possible options.
  The value for each option is 0 or 1.

  groupid    -- not supported yet
  encryption -- not supported yet
  compression -- Compresses frame before writing tag; 
                 compression/uncompression is done automatically
  read_only   -- Ignored by this library, should be obeyed by application
  file_preserv -- Ignored by this library, should be obeyed by application
  tag_preserv -- Ignored by this library, should be obeyed by application

=cut

sub get_frame_option {
    my ($self, $fname)=@_;
    $self->get_frame_ids() unless exists $self->{frameIDs};
    return undef unless exists $self->{frames}->{$fname};
    return $self->{frames}->{$fname}->{flags};
}

=pod

=item set_frame_option()

  $options = set_frame_option($ID, $option, $value);

  Set $option to $value (0 or 1). If successfull the new set of
  options is returned, undef otherwise.

  groupid    -- not supported yet
  encryption -- not supported yet
  compression -- Compresses frame before writing tag; 
                 compression/uncompression is done automatically
  read_only   -- Ignored by this library, should be obeyed by application
  file_preserv -- Ignored by this library, should be obeyed by application
  tag_preserv -- Ignored by this library, should be obeyed by application


=cut

sub set_frame_option {
    my ($self, $fname,$option,$value)=@_;
    $self->get_frame_ids() unless exists $self->{frameIDs};
    return undef unless exists $self->{frames}->{$fname};
    if (exists $self->{frames}->{$fname}->{flags}->{$option}) {
	    $self->{frames}->{$fname}->{flags}->{$option}=$value?1:0;
    } else {
	    warn "Unknown option $option\n";
	    return undef;
    }
    return $self->{frames}->{$fname}->{flags};
}

sub sort_with_apic {
  my ($a_APIC, $b_APIC) = map scalar(/^APIC/), $a, $b;
  $a_APIC cmp $b_APIC or $a cmp $b;
}

# build_tag()
# create a string with the complete tag data
sub build_tag {
    my ($self, $ignore_error) = @_;
    my $tag_data;

    # in which order should the frames be sorted?
    # with a simple sort the order of frames of one type is the order of adding them
    my @frames = sort sort_with_apic keys %{$self->{frames}};

    for my $frameid (@frames) {
  	    my $frame = $self->{frames}->{$frameid};

	    if ($frame->{major} < 3) {
		    #try to convert to ID3v2.3 or
		    warn "Can't convert $frameid to ID3v2.3\n";
		    next if ($ignore_error);
		    return undef;
	    }
	    my $data = $frame->{data};
	    my %flags = ();
	    #compress data if this is wanted
	    if ($frame->{flags}->{compression} || $self->{flags}->{compress_all}) {
		    $flags{compression} = 1;
		    $data = pack("N", length($data)) . compress $data unless $frame->{flags}->{unchanged};
	    }

	    #encrypt data if this is wanted
	    if ($frame->{flags}->{encryption} || $self->{flags}->{encrypt_all}) {
	            if ($frame->{flags}->{unchanged}) {
		            $flags{encryption} = 1;
		    } else {
		            # ... not supported yet
		            return undef unless $ignore_error;
		            warn "Encryption not supported yet\n";
		    }
	    }

	    # set groupid
	    if ($frame->{flags}->{group_id}) {
		    return undef unless $ignore_error;
		    warn "Group ids are not supported in writing\n";
	    }

	    # unsync
	    my $extra = 0;
	    if ( ($self->get_config('id3v23_unsync'))->[0]
		 and ($self->{version} == 3
		      and ($self->get_config('id3v23_unsync_size_w'))->[0]
		      or $self->{version} >= 4) ) {
	      $extra++ while $data =~ /\xFF(?=[\x00\xE0-\xFF])/g;
	    }

	    #prepare header
	    my $header = substr($frameid,0,4) . pack("Nn", $extra + length ($data), build_flags(%flags));

	    $tag_data .= $header . $data;
    }
    return $tag_data;
}

# insert_space() copies a mp3-file and can insert one or several areas
# of free space for a tag. These areas are defined as
# ($pos, $old_size, $new_size)
# $pos says at which position of the mp3-file the space should be inserted
# new_size gives the size of the space to insert and old_size can be used
# to skip this size in the mp3-file (e.g if 
sub insert_space {
	my ($self, $insert) = @_;
	my $mp3obj = $self->{mp3};
	# !! use a specific tmp-dir here
	my $tempfile = dirname($mp3obj->{filename}) . "/TMPxx";
	my $count = 0;
	while (-e $tempfile . $count . ".tmp") {
		if ($count++ > 999) {
			warn "Problems with tempfile\n";
			return undef;
		}
	}
	$tempfile .= $count . ".tmp";
	unless (open (NEW, ">$tempfile")) {
		warn "Can't open '$tempfile' to insert tag\n";
		return -1;
	}
	my ($buf, $pos_old);
	binmode NEW;
	$pos_old=0;
	$mp3obj->seek(0,0);
	local $\ = '';

	foreach my $ins (@$insert) {
		if ($pos_old < $ins->[0]) {
			$pos_old += $ins->[0];
			while ($mp3obj->read(\$buf,$ins->[0]<16384?$ins->[0]:16384)) {
				print NEW $buf;
				$ins->[0] = $ins->[0]<16384?0:$ins->[0]-16384;
			}
		}
		for (my $i = 0; $i<$ins->[2]; $i++) {
			print NEW chr(0);
		}
		if ($ins->[1]) {
			$pos_old += $ins->[1];
			$mp3obj->seek($pos_old,0);
		}
	}

	while ($mp3obj->read(\$buf,16384)) {
		print NEW $buf;
	}
	close NEW;
	$mp3obj->close;

	# rename tmp-file to orig file
	unless (( rename $tempfile, $mp3obj->{filename})||
	    (system("mv",$tempfile,$mp3obj->{filename})==0)) {
		unlink($tempfile);
		warn "Couldn't rename temporary file $tempfile to $mp3obj->{filename}\n";
		return -1;
	}
	return 0;
}

=pod

=item get_frames()

  ($name, @info) = get_frames($ID);
  ($name, @info) = get_frames($ID, 'raw');

Same as get_frame() with different order of the returned values.
$name and elements of the array @info have the same semantic as for
get_frame(); each frame with id $ID produces one elements of array @info.

=cut

sub get_frames {
    my ($self, $fname, $raw) = @_;
    my ($info, $name, @rest) = $self->get_frame($fname, $raw) or return;
    return ($name, $info, @rest);
}


=item as_bin()

  $tag2 = $id3v2->as_bin($ignore_error, $update_file, $raw_ok);

Returns the the current content of the ID3v2 tag as a string good to
write to a file; it contains all the necessary footers and headers.

If $ignore_error is TRUE, the frames the module does not know how to
write are skipped; otherwise it is an error to have such a frame.
Returns undef on error.

If the optional argument $update_file is TRUE, an additional action is
performed: if the audio file does not contain an ID3v2 tag, or the tag
in the file is smaller than the built ID3v2 tag, the necessary
0-padding is inserted before the audio content of the file so that it
is able to accommodate the build tag (and the C<tagsize> field of
$id3v2 is updated correspondingly); in any case the header length of
$tag2 is set to reflect the space in the beginning of the audio file.

Unless $update_file has C<'padding'> as a substring, the actual length of
the string $tag2 is not modified, so if it is smaller than the reserved
space in the file, one needs to add some 0 padding at the end.  Note that
if the size of reserved space can shrink (as with C<id3v2_shrink> configuration
option), then without this option it would be hard to calculate necessary
padding by hand.

If $raw_ok option is given, but not $update_file, the original contents
is returned for unmodified tags.

=item as_bin_raw()

  $tag2 = $id3v2->as_bin_raw($ignore_error, $update_file);

same as as_bin() with $raw_ok flag.

=item write_tag()

  $id3v2->write_tag($ignore_error);

Saves all frames to the file. It tries to update the file in place,
when the space of the old tag is big enough for the new tag.
Otherwise it creates a temp file with a new tag (i.e. copies the whole
mp3 file) and renames/moves it to the original file name.

An extended header with CRC checksum is not supported yet.

Encryption of frames and group ids are not supported. If $ignore_error
is set, these options are ignored and the frames are saved without these options.
If $ignore_error is not set and a tag with an unsupported option should be save, the
tag is not written and a 0 is returned.

If a tag with an encrypted frame is read, and the frame is not changed
it can be saved encrypted again.

ID3v2.2 tags are converted automatically to ID3v2.3 tags during
writing. If a frame cannot be converted automatically (PIC; CMR),
writing aborts and returns a 0. If $ignore_error is true, only not
convertable frames are ignored and not written, but the rest of the
tag is saved as ID3v2.3.

At the moment the tag is automatically unsynchronized.

If the tag is written successfully, 1 is returned.

=cut

sub as_bin_raw ($;$$) {
    my ($self, $ignore_error, $update_file) = @_;
    $self->as_bin($ignore_error, $update_file, 1);
}

sub as_bin ($;$$$) {
    my ($self, $ignore_error, $update_file, $raw_ok) = @_;

    return $self->{raw_data}
      if $raw_ok and $self->{raw_data} and not $self->{modified} and not $update_file;

    die "Writing of ID3v2.4 is not fully supported (prohibited now via `write_v24').\n"
      if $self->{major} == 4 and not $self->get_config1('write_v24');
    if ($self->{major} > 4) {
	    warn "Only writing of ID3v2.3 (and some tags of v2.4) is supported. Cannot convert ID3v".
	      $self->{version}." to ID3v2.3 yet.\n";
	    return undef;
    }

    # which order should tags have?

    $self->get_frame_ids;
    my $tag_data = $self->build_tag($ignore_error);
    return unless defined $tag_data;

    # printing this will ruin flags if they are \x80 or above.
    die "panic: prepared raw tag contains wide characters"
      if $tag_data =~ /[^\x00-\xFF]/;
    # perhaps search for first mp3 data frame to check if tag size is not
    # too big and will override the mp3 data

    #ext header are not supported yet
    my $flags = chr(0);
    $flags = chr(128) if ($self->get_config('id3v23_unsync'))->[0]
      and $tag_data =~ s/\xFF(?=[\x00\xE0-\xFF])/\xFF\x00/g;     # sync flag
    $tag_data .= "\0"		# Terminated by 0xFF?
	if length $tag_data and chr(0xFF) eq substr $tag_data, -1, 1;
    my $n_tsize = length $tag_data;

    my $header = 'ID3' . chr(3) . chr(0);

    if ($update_file) {
	my $o_tsize = $self->{buggy_padding_size} + $self->{tagsize};
	my $add_padding = 0;
	if ( $o_tsize < $n_tsize
	     or ($self->get_config('id3v2_shrink'))->[0] ) {
	    # if creating new tag / increasing size add at least 128b padding
	    # add additional bytes to make new filesize multiple of 512b
	    my $mp3obj = $self->{mp3};
	    my $filesize = (stat($mp3obj->{filename}))[7];
	    my $extra = ($self->get_config('id3v2_minpadding'))->[0];
	    my $n_filesize = ($filesize + $n_tsize - $o_tsize + $extra);
	    my $round = ($self->get_config('id3v2_sizemult'))->[0];
	    $n_filesize = (($n_filesize + $round - 1) & ~($round - 1));
	    my $n_padding = $n_filesize - $filesize - ($n_tsize - $o_tsize);
	    $n_tsize += $n_padding;
	    if ($o_tsize != $n_tsize) {
	      my @insert = [0, $o_tsize+10, $n_tsize + 10];
	      return undef unless insert_space($self, \@insert) == 0;
	    } else {	# Slot is not filled by 0; fill it manually
	      $add_padding = $n_padding - $self->{buggy_padding_size};
	    }
	    $self->{tagsize} = $n_tsize;
	} else {	# Include current "padding" into n_tsize
	    $add_padding = $self->{tagsize} - $n_tsize;
	    $n_tsize = $self->{tagsize} = $o_tsize;
        }
	$add_padding = 0 if $add_padding < 0;
	$tag_data .= "\0" x $add_padding if $update_file =~ /padding/;
    }

    #convert size to header format specific size
    my $size = unpack('B32', pack ('N', $n_tsize));
    substr ($size, -$_, 0) = '0' for (qw/28 21 14 7/);
    $size= pack('B32', substr ($size, -32));

    return "$header$flags$size$tag_data";
}

sub write_tag {
    my ($self,$ignore_error) = @_;
    $self->fix_frames_encoding()
	if $self->get_config1('id3v2_fix_encoding_on_write');

    $self->get_frame_ids;	# Ensure all the reading is done...
    # Need to do early, otherwise file size for calculation of "best" padding
    # may not take into account the added ID3v1 tag
    my $mp3obj = $self->{mp3};
    $mp3obj->close;
    unless ($mp3obj->open("write")) {
	warn "Couldn't open file `",$mp3obj->filename(),"' to write tag!";
	return undef;
    }

    my $tag = $self->as_bin($ignore_error, 'update_file, with_padding');
    return 0 unless defined $tag;

    $mp3obj->close;
    unless ($mp3obj->open("write")) { # insert_space() could've closed the file
	warn "Couldn't open file `",$mp3obj->filename(),"' to write tag!";
	return undef;
    }

    # actually write the tag
    $mp3obj->seek(0,0);
    $mp3obj->write($tag);
    $mp3obj->close;
    return 1;
}

=pod

=item remove_tag()

  $id3v2->remove_tag();

Removes the whole tag from the file by copying the whole
mp3-file to a temp-file and renaming/moving that to the
original filename.

Do not use remove_tag() if you only want to change a header,
as otherwise the file is copied unnecessarily. Use write_tag()
directly, which will override an old tag.

=cut 

sub remove_tag {
    my $self = shift;
    my $mp3obj = $self->{mp3};  
    my $tempfile = dirname($mp3obj->{filename}) . "/TMPxx";
    my $count = 0;
    local $\ = '';
    while (-e $tempfile . $count . ".tmp") {
	if ($count++ > 999) {
	    warn "Problems with tempfile\n";
	    return undef;
	}
    }
    $tempfile .= $count . ".tmp";
    if (open (NEW, ">$tempfile")) {
	my $buf;
	binmode NEW;
	$mp3obj->seek($self->{tagsize}+10,0);
	while ($mp3obj->read(\$buf,16384)) {
	    print NEW $buf;
	}
	close NEW;
	$mp3obj->close;
	unless (( rename $tempfile, $mp3obj->{filename})||
		(system("mv",$tempfile,$mp3obj->{filename})==0)) {
	    warn "Couldn't rename temporary file $tempfile\n";
	}
    } else {
	warn "Couldn't write temp file\n";
	return undef;
    }
    return 1;
}

=pod

=item add_frame()

  $fn = $id3v2->add_frame($fname, @data);

Add a new frame, identified by the short name $fname.  The number of
elements of array @data should be as described in the ID3v2.3
standard.  (See also L<MP3::Tag::ID3v2_Data>.)  There are two
exceptions: if @data is empty, it is filled with necessary number of
C<"">); if one of required elements is C<encoding>, it may be omitted
or be C<undef>, meaning the arguments are in "Plain Perl (=ISOLatin-1
or Unicode) encoding".

It returns the the short name $fn (which can differ from
$fname, when an $fname frame already exists). If no
other frame of this kind is allowed, an empty string is
returned. Otherwise the name of the newly created frame
is returned (which can have a 01 or 02 or ... appended).

You have to call write_tag() to save the changes to the file.

Examples (with C<$id3v2-E<gt>> omitted):

 $f = add_frame('TIT2', 0, 'Abba');   # $f='TIT2'
 $f = add_frame('TIT2', 'Abba');      # $f='TIT201', encoding=0 implicit

 $f = add_frame('COMM', 'ENG', 'Short text', 'This is a comment');

 $f = add_frame('COMM');              # creates an empty frame

 $f = add_frame('COMM', 'ENG');       # ! wrong ! $f=undef, becaues number 
                                      # of arguments is wrong

 $f = add_frame('RBUF', $n1, $n2, $n3);
 $f = add_frame('RBUF', $n1, $n2);	# last field of RBUF is optional

If a frame has optional fields I<and> C<encoding> (only C<COMR> frame
as of ID3v2.4), there may be an ambiguity which fields are omitted.
It is resolved this way: the C<encoding> field can be omitted only if
all other optional frames are omitted too (set it to C<undef>
instead).

=item add_frame_split()

The same as add_frame(), but if the number of arguments is
unsufficient, would split() the last argument on C<;> to obtain the
needed number of arguments.  Should be avoided unless it is known that
the fields do not contain C<;> (except for C<POPM RBUF RVRB SYTC>,
where splitting may be done non-ambiguously).

  # No ambiguity, since numbers do not contain ";":
  $f = add_frame_split('RBUF', "$n1;$n2;$n3");

For C<COMR> frame, in case when the fields are C<join()>ed by C<';'>,
C<encoding> field may be present only if all the other fields are
present.

=cut 

# 0 = latin1 (effectively: unknown)
# 1 = UTF-16 with BOM	(we always write UTF-16le to cowtow to M$'s bugs)
# 2 = UTF-16be, no BOM
# 3 = UTF-8
my @dec_types = qw( iso-8859-1 UTF-16   UTF-16BE utf8 );
my @enc_types = qw( iso-8859-1 UTF-16LE UTF-16BE utf8 );
my @tail_rex;

# Actually, disable this code: it always triggers unsync...
my $use_utf16le = $ENV{MP3TAG_USE_UTF_16LE};
@enc_types = @dec_types unless $use_utf16le;

sub _add_frame {
    my ($self, $split, $fname, @data) = @_;
    $self->get_frame_ids() unless exists $self->{frameIDs};
    my $format = get_format($fname);
    return undef unless defined $format;

    #prepare the data
    my $args = @$format; my $opt = 0;

    unless (@data) {
	@data = map {''} @$format;
    }

    my($encoding, $calc_enc, $e, $e_add) = (0,0); # Need to calculate encoding?
    # @data may be smaller than @args due to missing encoding, or due
    # to optional arguments.  Both may be applicable for COMR frames.
    if (@data < $args) {
      $_->{optional} and $opt++ for @$format;
      $e_add++, unshift @data, undef	# Encoding skipped
	if (@data == $args - 1 - $opt or $split and @data <= $args - 1 - $opt)
	  and $format->[0]->{name} eq '_encoding';
      if ($opt) {		# encoding is present only for COMR, require it
	die "Data for `encoding' should be between 0 and 3"
	  if $format->[0]->{name} eq "_encoding"
	    and defined $data[0] and not $data[0] =~ /^[0-3]?$/;
      }
    }
    if ($split and @data < $args) {
      if ($back_splt{$fname}) {
	my $c = $args - @data;
	my $last = pop @data;
	my $rx = ($tail_rex[$c] ||= qr/((?:;[^;]*){0,$c})\z/);
	my($tail) = ($last =~ /$rx/); # Will always match
	push @data, substr $last, 0, length($last)-length($tail);
	if ($tail =~ s/^;//) {	# matched >= 1 times
	  push @data, split ';', $tail;
	}
      } else {
	my $last = pop @data;
	push @data, split /;/, $last, $args - @data;
      }
      # Allow for explicit specification of encoding
      shift @data if @data == $args + 1 and not defined $data[0]
	and $format->[0]->{name} eq '_encoding'; # Was auto-put there
    }
    die "Unexpected number of fields: ".@data.", expect $args, optional=$opt"
      unless @data <= $args and @data >= $args - $opt;
    if ($format->[0]->{name} eq "_encoding" and not defined $data[0]) {
      $calc_enc = 1;
      shift @data;
    }

    my ($datastring, $have_high) = "";
    if ($calc_enc) {
        my @d = @data;
        foreach my $fs (@$format) {
            $have_high = 1 if $fs->{encoded} and $d[0] and $d[0] =~ /[^\x00-\xff]/;
            shift @d unless $fs->{name} eq "_encoding";
        }
    }
    foreach my $fs (@$format) {
	next if $fs->{optional} and not @data;
	if ($fs->{name} eq "_encoding") {
	    if ($calc_enc) {
		$encoding = ($have_high ? 1 : 0);	# v2.3 only has 0, 1
	    } else {
		$encoding = shift @data;
	    }
	    $datastring .= chr($encoding);
	    next;
	}
	my $d = shift @data;
	if ($fs->{isnum}) {
	  ## store data as number
	  my $num = int($d);
	  $d="";
 	  while ($num) { $d=pack("C",$num % 256) . $d; $num = int($num/256);}
	  if ( exists $fs->{len} and $fs->{len}>0 ) {
	    $d = substr $d, -$fs->{len};
	    $d = ("\x00" x ($fs->{len}-length($d))) . $d if length($d) < $fs->{len};
	  }
	  if ( exists $fs->{mlen} and $fs->{mlen}>0 ) {
	    $d = ("\x00" x ($fs->{mlen}-length($d))) . $d if length($d) < $fs->{mlen};
	  }
	} elsif ( exists $fs->{len} and not exists $fs->{func}) {
	  if ($fs->{len}>0) {
	    $d = substr $d, 0, $fs->{len};
	    $d .= " " x ($fs->{len}-length($d)) if length($d) < $fs->{len};
	  } elsif ($fs->{len}==0) {
	    $d .= chr(0);
	  }
	} elsif (exists $fs->{mlen} and $fs->{mlen}>0) {
	    $d .= " " x ($fs->{mlen}-length($d)) if length($d) < $fs->{mlen};
	}
        if (exists $fs->{re2b}) {
          while (my ($pat, $rep) = each %{$fs->{re2b}}) {
            $d =~ s/$pat/$rep/gis;
          }
        }
        if (exists $fs->{func_back}) {
	  $d = $fs->{func_back}->($d);
	} elsif (exists $fs->{func}) {
	  if ($fs->{small_max}) { # Allow the old way (byte) and a number
	    # No conflict possible: byte is always smaller than ord '0'
	    $d = pack 'C', $d if $d =~ /^\d+$/;
	  }
	  $d = $self->__format_field($fname, $fs->{name}, $d)
	}
	if ($fs->{encoded}) {
	  if ($encoding) {
	    # 0 = latin1 (effectively: unknown)
	    # 1 = UTF-16 with BOM (we write UTF-16le to cowtow to M$'s bugs)
	    # 2 = UTF-16be, no BOM
	    # 3 = UTF-8
	    require Encode;
	    if ($calc_enc or $encode_utf8) {	# e_u8==1 by default
	      $d = Encode::encode($enc_types[$encoding], $d);
	    } elsif ($encoding < 3) {
	      # Reencode from UTF-8
	      $d = Encode::decode('UTF-8', $d);
	      $d = Encode::encode($enc_types[$encoding], $d);
	    }
	    $d = "\xFF\xFE$d" if $use_utf16le and $encoding == 1;
	  } elsif (not $self->{fixed_encoding}	# Now $encoding == 0...
		   and $self->get_config1('id3v2_fix_encoding_on_edit')
		   and $e = $self->botched_encoding()
		   and do { require Encode; Encode::decode($e, $d) ne $d }) {
	    # If the current string is interpreted differently
	    # with botched_encoding, need to unbotch...
	    $self->fix_frames_encoding();
	  }
	}
	$datastring .= $d;
    }

    return add_raw_frame($self, $fname, $datastring);
}

sub add_frame {
  my $self = shift;
  _add_frame($self, 0, @_)
}

sub add_frame_split {
  my $self = shift;
  _add_frame($self, 1, @_)
}

sub add_raw_frame ($$$$) {
    my($self, $fname, $datastring, $flags) = (shift,shift,shift,shift);

    #add frame to tag
    if (exists $self->{frames}->{$fname}) {
        my ($c, $ID) = (1, $fname);
	$fname .= '01';
	while (exists $self->{frames}->{$fname}) {
	    $fname++, $c++;
	}
	++$self->{extra_frames}->{$ID}
	  if $c > ($self->{extra_frames}->{$ID} || 0);
    }
    $self->{frames}->{$fname} = {flags => ($flags || $self->check_flags(0)),
				 major => $self->{frame_major},
				 data => $datastring };
    $self->{modified}++;
    return $fname;
}

=pod

=item change_frame()

  $id3v2->change_frame($fname, @data);

Change an existing frame, which is identified by its
short name $fname eg as returned by get_frame_ids().
@data must be same as in add_frame().

If the frame $fname does not exist, undef is returned.

You have to call write_tag() to save the changes to the file.

=cut 

sub change_frame {
    my ($self, $fname, @data) = @_;
    $self->get_frame_ids() unless exists $self->{frameIDs};
    return undef unless exists $self->{frames}->{$fname};

    $self->remove_frame($fname);
    $self->add_frame($fname, @data);

    return 1;
}

=pod

=item remove_frame()

  $id3v2->remove_frame($fname);

Remove an existing frame. $fname is the short name of a frame,
eg as returned by get_frame_ids().

You have to call write_tag() to save the changes to the file.

=cut

sub remove_frame {
    my ($self, $fname) = @_;
    $self->get_frame_ids() unless exists $self->{frameIDs};
    return undef unless exists $self->{frames}->{$fname};
    delete $self->{frames}->{$fname};
    $self->{modified}++;
    return 1;
}

=item copy_frames($from, $to, $overwrite, [$keep_flags, $f_ids])

Copies specified frames between C<MP3::Tag::ID3v2> objects $from, $to.  Unless
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

sub copy_frames {
  my ($from, $to, $overwrite, $keep_flags, $f_ids) = @_;
#  return 0 unless $from->{ID3v2}; # No need to create it...
  my($cp, $expl) = (0, $f_ids);
  $f_ids ||= [keys %{$from->get_frame_ids}];
  for my $fn (@$f_ids) {
    next if not $expl and $fn =~ /^(GRID|TLEN)/;
    if (($overwrite || 0) eq 'delete') {
      $to->frame_select_by_descr($from->get_frame_descr($fn), undef); # delete
    } elsif (not $overwrite) {
      next if $to->frame_have($from->get_frame_descr($fn));
    }
    my $f = $from->{frames}->{$fn};
    $fn =~ s/^(\w{4})\d+$/$1/;
    my $d = $f->{data};
    my %fl = %{$f->{flags}};
    (substr $d, 0, 1) = '' if delete $fl{groupid};
    $to->add_raw_frame($fn, $d, $keep_flags ? \%fl : undef);
    $cp++;
  }
  return $cp
}

=item is_modified()

  $id3v2->is_modified;

Returns true if the tag was modified after it was created.

=cut

sub is_modified {
    shift->{modified}
}

=pod

=item supported_frames()

  $frames = $id3v2->supported_frames();

Returns a hash reference with all supported frames. The keys of the
hash are the short names of the supported frames, the 
according values are the long (english) names of the frames.

=cut

sub supported_frames {
    my $self = shift;

    my (%tags, $fname, $lname);
    while ( ($fname, $lname) = each %long_names) {
	$tags{$fname} = $lname if get_format($fname, "quiet");
    }

    return \%tags;
}

=pod 

=item what_data()

  ($data, $res_inp, $data_map) = $id3v2->what_data($fname);

Returns an array reference with the needed data fields for a
given frame.
At this moment only the internal field names are returned,
without any additional information about the data format of
this field. Names beginning with an underscore (normally '_data')
can contain binary data.  (The C<_encoding> field is skipped in this list,
since it is usually auto-deduced by this module.)

$resp_inp is a reference to a hash (keyed by the field name) describing
restrictions for the content of the data field.
If the entry is undef, no restriction exists. Otherwise it is a hash.
The keys of the hash are the allowed input, the correspodending value
is the value which is actually stored in this field. If the value
is undef then the key itself is valid for saving.
If the hash contains an entry with "_FREE", the hash contains
only suggestions for the input, but other input is also allowed.

$data_map contains values of $resp_inp in the order of fields of a frame
(including C<_encoding>).

Example for picture types of the APIC frame:

  {"Other"                               => "\x00",
   "32x32 pixels 'file icon' (PNG only)" => "\x01",
   "Other file icon"                     => "\x02",
   ...}

=cut

sub what_data {
    my ($self, $fname) = @_;
    $fname = substr $fname, 0, 4;   # delete 01 etc. at end
    return if length($fname)==3;    #id3v2.2 tags are read-only and should never be written
    my $reswanted = wantarray;
    my $format = get_format($fname, "quiet");
    return unless defined $format;
    my (@data, %res, @datares);

    foreach (@$format) {
        next unless exists $_->{name};
	push @data, $_->{name} unless $_->{name} eq "_encoding";
	next unless $reswanted;
	my $key = $fname . $_->{name};
	$res{$_->{name}} = $field_map{$key} if exists $field_map{$key};
	push @datares, $field_map{$key};
    }

    return(\@data, \%res, \@datares) if $reswanted;
    return \@data;
}

sub __format_field {
    my ($self, $fname, $nfield, $v) = @_;
    # $v =~ s/^(\d+)$/chr $1/e if $is_small_int{"$fname$nfield"};	# Already done by caller

    my $m = $field_map_back{my $t = "$fname$nfield"} or return $v; # packed ==> Human
    return $v if exists $m->{$v}; # Already of a correct form

    my $m1 = $field_map{$t} or die; # Human ==> packed
    return $m1->{$v} if exists $m1->{$v}; # translate
    return $v if $m->{_FREE};	# Free-form allowed

    die "Unsupported value `$v' for field `$nfield' of frame `$fname'";
}

=item title( [@new_title] )

Returns the title composed of the tags configured via C<MP3::Tag-E<gt>config('v2title')>
call (with default 'Title/Songname/Content description' (TIT2)) from the tag.
(For backward compatibility may be called by deprecated name song() as well.)

Sets TIT2 frame if given the optional arguments @new_title.  If this is an
empty string, the frame is removed.

=cut

*song = \&title;

sub v2title_order {
    my $self = shift;
    @{ $self->get_config('v2title') };
}

sub title {
    my $self = shift;
    if (@_) {
	$self->remove_frame('TIT2'); # NOP if it is not there
	return if @_ == 1 and $_[0] eq '';
	return $self->add_frame('TIT2', @_);
    }
    my @parts = grep defined && length,
	map scalar $self->get_frame($_), $self->v2title_order;
    return unless @parts;
    my $last = pop @parts;
    my $part;
    for $part (@parts) {
	$part =~ s(\0)(///)g;		# Multiple strings
	$part .= ',' unless $part =~ /[.,;:\n\t]\s*$/;
	$part .= ' ' unless $part =~ /\s$/;
    }
    return join '', @parts, $last;
}

=item _comment([$language])

Returns the file comment (COMM with an empty 'Description') from the tag, or
"Subtitle/Description refinement" (TIT3) frame (unless it is considered a part
of the title).

=cut

sub _comment {
    my $self = shift;
    my $language;
    $language = lc shift if @_;
    my @info = get_frames($self, "COMM");
    shift @info;
    for my $comment (@info) {
	next unless defined $comment; # Removed frames
	next unless exists $comment->{Description} and not length $comment->{Description};
	next if defined $language and (not exists $comment->{Language}
				       or lc $comment->{Language} ne $language);
	return $comment->{Text};
    }
    return if grep $_ eq 'TIT3', $self->v2title_order;
    return scalar $self->get_frame("TIT3");
}

=item comment()

   $val = $id3v2->comment();
   $newframe = $id3v2->comment('Just a comment for freddy', 'personal', 'eng');

Returns the file comment (COMM frame with the 'Description' field in
C<default_descr_c> configuration variable, defalting to C<''>) from
the tag, or "Subtitle/Description refinement" (TIT3) frame (unless it
is considered a part of the title).

If optional arguments ($comment, $short, $language) are present, sets
the comment frame.  If $language is omited, uses the
C<default_language> configuration variable (default is C<XXX>).  If not
C<XXX>, this should be lowercase 3-letter abbreviation according to
ISO-639-2).

If $short is not defined, uses the C<default_descr_c> configuration
variable.  If $comment is an empty string, the frame is removed.

=cut

sub comment {
    my $self = shift;
    my ($comment, $short, $language) = @_  or return $self->_comment();
    my @info = get_frames($self, "COMM");
    my $desc = ($self->get_config('default_descr_c'))->[0];
    shift @info;
    my $c = -1;
    for my $comment (@info) {
	++$c;
	next unless defined $comment; # Removed frames
	next unless exists $comment->{Description}
	  and $comment->{Description} eq $desc;
	next if defined $language and (not exists $comment->{Language}
				       or lc $comment->{Language} ne lc $language);
	$self->remove_frame($c ? sprintf 'COMM%02d', $c : 'COMM');
	# $c--;				# Not needed if only one frame is removed
	last;
    }
    return if @_ == 1 and $_[0] eq '';
    $language = ($self->get_config('default_language'))->[0]
      unless defined $language;
    $short = $desc       unless defined $short;
    $self->add_frame('COMM', $language, $short, $comment);
}

=item frame_select($fname, $descrs, $languages [, $newval1, ...])

Used to get/set/delete frames which may be not necessarily unique in a tag.

   # Select short-description='', prefere language 'eng', then 'rus', then
   # the third COMM frame, then any (in this case, the first or the second)
   # COMM frame
   $val = $id3v2->frame_select('COMM', '', ['eng', 'rus', '#2', '']); # Read
   $new = $id3v2->frame_select('COMM', '', ['eng', 'rus', '#2'],      # Write
			       'Comment with empty "Description" and "eng"');
   $new = $id3v2->frame_select('COMM', '', ['eng', 'rus', '#2'],      # Delete
			       undef);

Returns the contents of the first frame named $fname with a
'Description' field in the specified array reference $descrs and the
language in the list of specified languages $languages; empty return
otherwise.  If the frame is a "simple frame", the frame is returned as
a string, otherwise as a hash reference; a "simple frame" should
consist of one of Text/URL/_Data fields, with possible addition of
Language and Description fields (if the corresponding arguments were
defined).

The lists $descrs and $languages of one element can be flattened to
become this element (as with C<''> above).  If the lists are not
defined, no restriction is applied; to get the same effect with
defined arguments, use $languages of C<''>, and/or $descrs a hash
reference.  Language of the form C<'#NUMBER'> selects the NUMBER's
(0-based) frame with frame name $fname.

If optional arguments C<$newval1...> are given, B<ALL> the found frames are
removed;  if only one such argument C<undef> is given, this is the only action.
Otherwise, a new frame is created afterwards (the first
elements of $descrs and $languages are used as the short description
and the language, defaulting to C<''> and the C<default_language>
configuration variable (which, in turn, defaults to C<XXX>; if not C<XXX>,
this should be lowercase 3-letter abbreviation according to ISO-639-2).
If new frame is created, the frame's name is returned; otherwise the count of
removed frames is returned.

As a generalization, APIC frames are handled too, using C<Picture
Type> instead of C<Language>, and auto-calculating C<MIME type> for
(currently) TIFF/JPEG/GIF/PNG/BMP and octet-stream.  Only frames with
C<MIME type> coinciding with the auto-calculated value are considered
as "simple frames".  One can use both the 1-byte format for C<Picture
Type>, and the long names used in the ID3v2 documentation; the default
value is C<'Cover (front)'>.

   # Choose APIC with empty description, picture_type='Leaflet page'
   my $data = $id3v2->frame_select('APIC', '', 'Leaflet page')
       or die "no expected APIC frame found";
   my $format = ( ref $data ? $data->{'MIME type'}
			    : $id3v2->_Data_to_MIME($data) );
   # I know what to do with application/pdf only (sp?) and 'image/gif'
   die "Do not know what to do with this APIC format: `$format'"
       unless $format eq 'application/pdf' or $format eq 'image/gif';
   $data = $data->{_Data} if ref $data;		# handle non-simple frame

   # Set APIC frame with empty description (front cover if no other present)
   # from content of file.gif
   my $data = do { open my $f, '<', 'file.gif' and binmode $f or die;
		   undef $/; <$f>};
   my $new_frame = $id3v2->frame_select('APIC', '', undef, $data);

Frames with multiple "content" fields may be set by providing multiple
values to set.  Alternatively, one can also C<join()> the values with
C<';'> if the splitting is not ambiguous, e.g., for C<POPM RBUF RVRB
SYTC>.  (For frames C<GEOD> and C<COMR>, which have a C<Description>
field, it should be specified among these values.)

   $id3v2->frame_select("RBUF", undef, undef, $n1, $n2, $n3);
   $id3v2->frame_select("RBUF", undef, undef, "$n1;$n2;$n3");

(By the way: consider using the method select_id3v2_frame() on the
"parent" MP3::Tag object instead [see L<MP3::Tag/select_id3v2_frame>],
or L<frame_select_by_descr()>.)

=item _Data_to_MIME

Internal method to extract MIME type from a string the image file
content.  Returns C<application/octet-stream> for unrecognized data
(unless extra TRUE argument is given).

  $format = $id3v2->_Data_to_MIME($data);

Currently, only the first 4 bytes of the string are inspected.

=cut

sub __to_lang($$) {my $l = shift; return $l if shift or $l eq 'XXX'; lc $l}

my %as_lang = ('APIC', ['Picture Type', chr 3, 'small_int']); # "Cover (front)"
my %MT = ("\xff\xd8\xff\xe0" => 'image/jpeg', "MM\0*" => 'image/tiff',
	   "II*\0" => 'image/tiff', "\x89PNG",
	  qw(image/png GIF8 image/gif BM image/bmp));

sub _Data_to_MIME ($$;$) {
  my($self, $data, $force) = (shift, shift, shift);  # Fname, field name remain
  my $res = $MT{substr $data, 0, 4} || $MT{substr $data, 0, 2};
  return $res if $res;
  return 'audio/mpeg' if $data =~ /^\xff[\xe0-\xff]/;	# 11 bits are 1
  return 'application/octet-stream' unless $force;
  return;
}

sub _frame_select {		# if $extract_content false, return all found
    # "Quadratic" in number of comment frames and select-short/lang specifiers
    my ($self, $extract_content, $fname) = (shift, shift, shift);
    my ($descr, $languages) = (shift, shift);
#      or ($fname eq 'COMM' and return $self->_comment());	# ???
    my $any_descr;
    if (ref $descr eq 'HASH') { # Special case
      $any_descr = 1;
      undef $descr;
    } elsif (defined $descr and not ref $descr) {
      $descr = [$descr];
    }
    my $lang_special = $as_lang{$fname};
    my $lang_field = ($lang_special ? $lang_special->[0] : 'Language');
    my $languages_mangled;

    if (defined $languages) {
	$languages = [$languages] unless ref $languages;
	$languages = [@$languages];	# Make a copy: we edit the entries...
	if ($lang_special) {
	  my $m = $field_map{"$fname$lang_field"};
	  if ($m) {	# Below we assume that mapped values are not ''...
	    # Need to duplicate the logic in add_frame() here, since
	    # we need a normalized form to compare frames-to-select with...
	    if ($lang_special->[2]) {	# small_int
		s/^(\d+)$/chr $1/e for @$languages;
	    }
	    @$languages_mangled = map( (exists $m->{$_} ? $m->{$_} : $_), @$languages);
	    my $m1 = $field_map_back{"$fname$lang_field"} or die;
	    my $loose = $m->{_FREE};
	    @$languages = map( (exists $m1->{$_} ? $m1->{$_} : $_), @$languages_mangled);
	    $_ eq '' or exists $m1->{$_} or $loose or not /\D/
	      or die "Unknown value `$_' for field `$lang_field' of frame $fname"
		for @$languages_mangled;
	  }
	} else {
	  @$languages = map __to_lang($_, 0), @$languages;
	}
    }
    my @found_frames = get_frames($self, $fname);
    shift @found_frames;
    my(@by_lang) = (0..$#found_frames);
    # Do it the slow way...
    if (defined $languages) {
	@by_lang = ();
	my %seen;
	for my $l (@$languages) {
	    if ($l =~ /^#(\d+)$/) {
		push @by_lang, $1 if not $seen{$1}++ and $1 < @found_frames;
	    } elsif (length $l > 3 and not $lang_special) {
		die "Language `$l' should not be more than 3-chars long";
	    } else {
		for my $c (0..$#found_frames) {
		    my $f = $found_frames[$c] or next;	# XXXX Needed?
		    push @by_lang, $c
			if ($l eq ''
			    or ref $f and defined $f->{$lang_field}
				      and $l eq __to_lang $f->{$lang_field}, $lang_special)
			    and not $seen{$c}++;
		}
	    }
	}
    }
    my @select;
    for my $c (@by_lang) {
	my $f = $found_frames[$c];
	my $cc = [$c, $f];
	push(@select, $cc), next unless defined $descr;
	push @select, $cc
	    if defined $f and ref $f and defined $f->{Description}
		 and grep $_ eq $f->{Description}, @$descr;
    }
    return @select unless $extract_content;
    unless (@_) {			# Read-only access
	return unless @select;
	my $res = $select[0][1]; # Only defined frames here...
	return $res unless ref $res; # TLEN
	my $ic = my $c = keys %$res;
	$c-- if exists $res->{Description} and (defined $descr or $any_descr);
	$c-- if exists $res->{$lang_field} and defined $languages;
	$c-- if exists $res->{encoding};
	$c-- if $c == 2 and $ic == 5 and exists $res->{'MIME type'}
		and exists $res->{_Data}
		and $res->{'MIME type'} eq $self->_Data_to_MIME($res->{_Data});
	if ($c <= 1) {
	  return $res->{Text}  if exists $res->{Text};
	  return $res->{URL}   if exists $res->{URL};
	  return $res->{_Data} if exists $res->{_Data};
        }
	return $res;
    }
    # Write or delete
    for my $f (reverse @select) { # Removal may break the numeration???
	my ($c, $frame) = @$f;
	$self->remove_frame($c ? sprintf('%s%02d', $fname, $c) : $fname);
    }
    return scalar @select unless @_ > 1 or defined $_[0];	# Delete
    if (defined $languages) {
      $languages = $languages_mangled if defined $languages_mangled;
    } elsif ($lang_special) {
      $languages = [$lang_special->[1]];
    } else {
      $languages = [@{$self->get_config('default_language')}]; # Copy to modify
    }
    my $format = get_format($fname);
    my $have_lang = grep $_->{name} eq $lang_field, @$format;
    $#$languages = $have_lang - 1; # Truncate
    unshift @$languages, $self->_Data_to_MIME($_[0])
      if $lang_special and @_ == 1;		# "MIME type" field
    $descr = ['']       unless defined $descr;
    my $have_descr = grep $_->{name} eq 'Description', @$format;
    $have_descr = 0 if $embedded_Descr{$fname};	# Must be explicitly provided
    $#$descr = $have_descr - 1;   # Truncate
    $self->add_frame_split($fname, @$languages, @$descr, @_) or die;
}

sub frame_select {
    my $self = shift;
    $self->_frame_select(1, @_);
}

=item frame_list()

Same as frame_select(), but returns the list of found frames, each an
array reference C<[$N, $f]> with $N the 0-based ordinal (among frames
with the given short name), and $f the contents of a frame.

=item frame_have()

Same as frame_select(), but returns the count of found frames.

=item frame_select_by_descr()

=item frame_have_by_descr()

=item frame_list_by_descr()

  $c = $id3v2->frame_select_by_descr("COMM(fre,fra,eng,#0)[]");
  $t = $id3v2->frame_select_by_descr("TIT2");
       $id3v2->frame_select_by_descr("TIT2", "MyT"); # Set/Change
       $id3v2->frame_select_by_descr("RBUF", $n1, $n2, $n3); # Set/Change
       $id3v2->frame_select_by_descr("RBUF", "$n1;$n2;$n3"); # Set/Change
       $id3v2->frame_select_by_descr("TIT2", undef); # Remove

Same as frame_select(), frame_have(), frame_list(), but take one string
argument instead of $fname, $descrs, $languages.  The argument should
be of the form

  NAME(langs)[descr]

Both C<(langs)> and C<[descr]> parts may be omitted; I<langs> should
contain comma-separated list of needed languages; no protection by
backslashes is needed in I<descr>.  frame_select_by_descr() will
return a hash if C<(lang)> is omited, but the frame has a language
field; likewise for C<[descr]>; see below for alternatives.

Remember that when frame_select_by_descr() is used for modification,
B<ALL> found frames are deleted before a new one is added.

(By the way: consider using the method select_id3v2_frame_by_descr() on the
"parent" MP3::Tag object instead; see L<MP3::Tag/select_id3v2_frame_by_descr>.)

=item frame_select_by_descr_simple()

Same as frame_select_by_descr(), but if no language is given, will not
consider the frame as "complicated" frame even if it contains a
language field.

=item frame_select_by_descr_simpler()

Same as frame_select_by_descr_simple(), but if no C<Description> is
given, will not consider the frame as "complicated" frame even if it
contains a C<Description> field.

=cut

sub frame_have {
    my $self = shift;
    scalar $self->_frame_select(0, @_);
}

sub frames_list {
    my $self = shift;
    $self->_frame_select(0, @_);
}

sub _frame_select_by_descr {
    my ($self, $what, $d) = (shift, shift, shift);
    my($l, $descr) = ('');
    if ( $d =~ s/^(\w{4})(?:\(([^()]*(?:\([^()]+\)[^()]*)*)\))?(?:\[(.*)\])?$/$1/ ) {
      $l = defined $2 ? [split /,/, $2, -1] : ($what > 1 && !@_ ? '' : undef);
      # Use special case in _frame_select:
      $descr = defined $3 ? $3 : ($what > 2 && !@_ ? {} : undef);
      # $descr =~ s/\\([\\\[\]])/$1/g if defined $descr;
    }
    return $self->_frame_select($what, $d, $descr, $l, @_);
}

sub frame_have_by_descr {
    my $self = shift;
    scalar $self->_frame_select_by_descr(0, @_);
}

sub frame_list_by_descr {
    my $self = shift;
    $self->_frame_select_by_descr(0, @_);
}

sub frame_select_by_descr {
    my $self = shift;
    $self->_frame_select_by_descr(1, @_);
}

sub frame_select_by_descr_simple {
    my $self = shift;
    $self->_frame_select_by_descr(2, @_); # 2 ==> prefer $languages eq ''...
}

sub frame_select_by_descr_simpler {
    my $self = shift;
    $self->_frame_select_by_descr(3, @_); # 2 ==> prefer $languages eq ''...
}

=item year( [@new_year] )

Returns the year (TYER/TDRC) from the tag.

Sets TYER and TDRC frames if given the optional arguments @new_year.  If this
is an empty string, the frame is removed.

The format is similar to timestamps of IDv2.4.0, but ranges can be separated
by C<-> or C<-->, and non-contiguous dates are separated by C<,> (comma).  If
periods need to be specified via duration, then one needs to use the ISO 8601
C</>-notation  (e.g., see

  http://www.mcs.vuw.ac.nz/technical/software/SGML/doc/iso8601/ISO8601.html

); the C<duration/end_timestamp> is not supported.

On output, ranges of timestamps are converted to C<-> or C<--> separated
format depending on whether the timestamps are years, or have additional
fields.

If configuration variable C<year_is_timestamp> is false, the return value
is always the year only (of the first timestamp of a composite timestamp).

Recall that ID3v2.4.0 timestamp has format yyyy-MM-ddTHH:mm:ss (year, "-",
month, "-", day, "T", hour (out of
24), ":", minutes, ":", seconds), but the precision may be reduced by
removing as many time indicators as wanted. Hence valid timestamps
are
yyyy, yyyy-MM, yyyy-MM-dd, yyyy-MM-ddTHH, yyyy-MM-ddTHH:mm and
yyyy-MM-ddTHH:mm:ss. All time stamps are UTC. For durations, use
the slash character as described in 8601, and for multiple noncontiguous
dates, use multiple strings, if allowed by the frame definition.

=cut

sub year {
    my $self = shift;
    if (@_) {
	$self->remove_frame('TYER') if defined $self->get_frame( "TYER");
	$self->remove_frame('TDRC') if defined $self->get_frame( "TDRC");
	return if @_ == 1 and $_[0] eq '';
	my @args = @_;
	$args[-1] =~ s/^(\d{4}\b).*/$1/;
	$self->add_frame('TYER', @args);	# Obsolete
	@args = @_;
	$args[-1] =~ s/-(-|(?=\d{4}\b))/\//g;	# ranges are /-separated
	$args[-1] =~ s/,(?=\d{4}\b)/\0/g;	# dates are \0-separated
	$args[-1] =~ s#([-/T:])(?=\d(\b|T))#${1}0#g;	# %02d-format
	return $self->add_frame('TDRC', @args);	# new; allows YYYY-MM-etc as well
    }
    my $y;
    ($y) = $self->get_frame( "TDRC", 'intact')
	or ($y) = $self->get_frame( "TYER") or return;
    return substr $y, 0, 4 unless ($self->get_config('year_is_timestamp'))->[0];
    # Convert to human-readable form
    $y =~ s/\0/,/g;
    my $sep = ($y =~ /-/) ? '--' : '-';
    $y =~ s#/(?=\d)#$sep#g;
    return $y;
}

=pod

=item track( [$new_track] )

Returns the track number (TRCK) from the tag.

Sets TRCK frame if given the optional arguments @new_track.  If this is an
empty string or 0, the frame is removed.

=cut

sub track {
    my $self = shift;
    if (@_) {
	$self->remove_frame('TRCK') if defined $self->get_frame("TRCK");
	return if @_ == 1 and not $_[0];
	return $self->add_frame('TRCK', @_);
    }
    return scalar $self->get_frame("TRCK");
}

=pod

=item artist( [ $new_artist ] )

Returns the artist name; it is the first existing frame from the list of

  TPE1      Lead artist/Lead performer/Soloist/Performing group
  TPE2      Band/Orchestra/Accompaniment
  TCOM      Composer
  TPE3      Conductor
  TEXT      Lyricist/Text writer

Sets TPE1 frame if given the optional arguments @new_artist.  If this is an
empty string, the frame is removed.

=cut

sub artist {
    my $self = shift;
    if (@_) {
	$self->remove_frame('TPE1') if defined $self->get_frame( "TPE1");
	return if @_ == 1 and $_[0] eq '';
	return $self->add_frame('TPE1', @_);
    }
    my $a;
    ($a) = $self->get_frame("TPE1") and return $a;
    ($a) = $self->get_frame("TPE2") and return $a;
    ($a) = $self->get_frame("TCOM") and return $a;
    ($a) = $self->get_frame("TPE3") and return $a;
    ($a) = $self->get_frame("TEXT") and return $a;
    return;
}

=pod

=item album( [ $new_album ] )

Returns the album name (TALB) from the tag.  If none is found, returns
the "Content group description" (TIT1) frame (unless it is considered a part
of the title).

Sets TALB frame if given the optional arguments @new_album.  If this is an
empty string, the frame is removed.

=cut

sub album {
    my $self = shift;
    if (@_) {
	$self->remove_frame('TALB') if defined $self->get_frame( "TALB");
	return if @_ == 1 and $_[0] eq '';
	return $self->add_frame('TALB', @_);
    }
    my $a;
    ($a) = $self->get_frame("TALB") and return $a;
    return if grep $_ eq 'TIT1', $self->v2title_order;
    return scalar $self->get_frame("TIT1");
}

=item genre( [ $new_genre ] )

Returns the genre string from TCON frame of the tag.

Sets TCON frame if given the optional arguments @new_genre.  If this is an
empty string, the frame is removed.

=cut

sub genre {
    my $self = shift;
    if (@_) {
	$self->remove_frame('TCON') if defined $self->get_frame( "TCON");
	return if @_ == 1 and $_[0] eq '';
	return $self->add_frame('TCON', @_);	# XXX add genreID 0x00 ?
    }
    my $g = $self->get_frame('TCON');
    return unless defined $g;
    $g =~ s/^\d+\0(?:.)//s;		# XXX Shouldn't this be done in TCON()?
    $g;
}

=item version()

  $version = $id3v2->version();
  ($major, $revision) = $id3v2->version();

Returns the version of the ID3v2 tag. It returns a formatted string
like "3.0" or an array containing the major part (eg. 3) and revision
part (eg. 0) of the version number. 

=cut

sub version {
    my ($self) = @_;
    if (wantarray) {
          return ($self->{major}, $self->{revision});
    } else {
	  return $self->{version};
    }
}

=item new()

  $tag = new($mp3fileobj);

C<new()> needs as parameter a mp3fileobj, as created by C<MP3::Tag::File>.  
C<new> tries to find a ID3v2 tag in the mp3fileobj. If it does not find a
tag it returns undef.  Otherwise it reads the tag header, as well as an
extended header, if available. It reads the rest of the tag in a
buffer, does unsynchronizing if necessary, and returns a
ID3v2-object.  At this moment only ID3v2.3 is supported. Any extended
header with CRC data is ignored, so no CRC check is done at the
moment.  The ID3v2-object can be used to extract information from
the tag.

Please use

   $mp3 = MP3::Tag->new($filename);
   $mp3->get_tags();                 ## to find an existing tag, or
   $id3v2 = $mp3->new_tag("ID3v2");  ## to create a new tag

instead of using this function directly

=cut

sub new {
    my ($class, $mp3obj, $create, $r_header) = @_;
    my $self={mp3=>$mp3obj};
    my $header=0;
    bless $self, $class;

    if (defined $mp3obj) {	# Not fake
      $mp3obj->open or return unless $mp3obj->is_open;
      $mp3obj->seek(0,0);
      $mp3obj->read(\$header, 10);
      $$r_header = $header if $r_header and 10 == length $header;
    }
    $self->{frame_start}=0;
    # default ID3v2 version
    $self->{major}=3;
    $self->{frame_major}=3;	# major for new frames
    $self->{revision}=0;
    $self->{version}= "$self->{major}.$self->{revision}";

    if (defined $mp3obj and $self->read_header($header)) {
	if ($create) {
	    $self->{tag_data} = '';
	    $self->{data_size} = 0;
	} else {
	    # sanity check:
	    my $s = $mp3obj->size;
	    my $s1 = $self->{tagsize} + $self->{footer_size};
	    if (defined $s and $s - 10 < $s1) {
	      warn "Ridiculously large tag size: $s1; file size $s";
	      return;
	    }
	    $mp3obj->read(\$self->{tag_data}, $s1);
	    $self->{data_size} = $self->{tagsize};
	    $self->{raw_data} = $header . $self->{tag_data};
	    # un-unsynchronize comes in all versions first
	    if ($self->{flags}->{unsync}) {
		my $hits = $self->{tag_data} =~ s/\xFF\x00/\xFF/gs;
		$self->{data_size} -= $hits;
	    }
	    # in v2.2.x complete tag may be compressed, but compression isn't
	    # described in tag specification, so get out if compression is found
	    if ($self->{flags}->{compress_all}) {
		    # can we test if it is simple zlib compression and use this?
		    warn "ID3v".$self->{version}." [whole tag] compression isn't supported. Cannot read tag\n";
		    return undef;
	    }
	    # read the ext header if it exists
	    if ($self->{flags}->{extheader}) {
		$self->{extheader} = substr ($self->{tag_data}, 0, 14);
		unless ($self->read_ext_header()) {
		    return undef; # ext header not supported
		}
	    }
	    $self->{footer} = substr $self->{tag_data}, -$self->{footer_size}
		if $self->{footer_size};
	    # Treat (illegal) padding after the tag
	    my($merge, $d, $z, $r) = ($mp3obj->get_config('id3v2_mergepadding'))->[0];
	    my $max0s = $merge ? 1e100 : 16*1024;
	    while ($max0s and $mp3obj->read(\$d, 1024)) {
		  $max0s -= length $d;
		  ($z) = ($d =~ /^(\0*)/);
		  $self->{buggy_padding_size} += length $z if $merge;
		  ($r = substr $d, length $z), last unless length($z) == length($d);
	    }
	    $self->{tagend_offset} = $mp3obj->tell() - length $r;
	    $mp3obj->read(\$d, 10 - length $r) and $r .= $d if defined $r and length $r < 10;
	    $$r_header = $d if $r_header and 10 <= length $d;
	}
	$mp3obj->close;
	return $self;
    } else {
	$mp3obj->close if defined $mp3obj;
	if (defined $create && $create) {
	    $self->{tag_data}='';
	    $self->{tagsize} = -10;
	    $self->{data_size} = 0;
	    $self->{buggy_padding_size} = 0;
	    return $self;
	}
    }
    return undef;
}

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    my $header;
    my $new = $class->new($filename, undef, \$header);
    $parent->[0]{header} = $header if $header and $parent;
    return unless $new;
    $new->{parent} = $parent;
    $new;
}

##################
##
## internal subs
##

# This sub tries to read the header of an ID3v2 tag and checks for the right header
# identification for the tag. It reads the version number of the tag, the tag size
# and the flags.
# Returns true if it finds a known ID3v2.x header, false otherwise.

sub read_header {
	my ($self, $header) = @_;
	my %params;

	if (substr ($header,0,3) eq "ID3") {
		# flag meaning for all supported ID3v2.x versions
		my @flag_meaning=([],[], # v2.0 and v2.1 aren't supported yet
				# 2.2
			       ["unknown","unknown","unknown","unknown","unknown","unknown","compress_all","unsync"],
				# 2.3
			       ["unknown","unknown","unknown","unknown","unknown","experimental","extheader","unsync"],
				# 2.4
			       ["unknown","unknown","unknown","unknown","footer","experimental","extheader","unsync"],
				# ????
			       #["unknown","unknown","unknown","unknown","footer","experimental","extheader","unsync"],
			      );

		# extract the header data
		my ($major, $revision, $pflags) = unpack ("x3CCC", $header);
		# check the version
		if ($major > $#supported_majors or $supported_majors[$major] == 0) {
			my $warn = "Unknown ID3v2-Tag version: v2.$major.$revision\n";
			$warn .= "| $major > ".($#supported_majors)." || $supported_majors[$major] == 0\n";

			if($major > $#supported_majors) {
			  $warn .= "| major $major > ".($#supported_majors)."\n";
			} else {
			  $warn .= "| \$supported_majors[major=$major] == 0\n";
			}
			$warn .= "$_: \$supported_majors[$_] = $supported_majors[$_]\n"
			  for (0..$#supported_majors);
			warn $warn;
			return 0;
		}
		if ($major == 4 and $self->get_config1('prohibit_v24')) {
			warn "Reading ID3v2-Tag version: v2.$major.$revision is prohibited via setting `prohibit_v24'\n";
			return 0;
		}
		if ($revision != 0) {
			warn "Unknown ID3v2-Tag revision: v2.$major.$revision\nTrying to read tag\n";
		}
		# check the flags
		my $flags={};
		my $unknownFlag=0;
		my $i=0;
	 	foreach (split (//, unpack('b8',pack('v',$pflags)))) {
 			$flags->{$flag_meaning[$major][$i]}=1 if $_;
			$i++;
		}
		$self->{version}  = "$major.$revision";
		$self->{major}    = $major;
		$self->{revision} = $revision;
		# 2.3: includes extHeader, frames (as written), and the padding
		#	excludes the header size (10)
		# 2.4: also excludes the footer (10 if present)
		$self->{tagsize} = un_syncsafe_4bytes substr $header, 6, 4;
		$self->{buggy_padding_size} = 0;	# Fake so far
		$self->{flags} = $flags;
		$self->{footer_size} = ($self->{flags}->{footer} ? 10 : 0);
		return 1;
	}
	return 0; # no ID3v2-Tag found
}

# Reads the extended header and adapts the internal counter for the start of the
# frame data. Ignores the rest of the ext. header (as CRC data).

# v2.3:
#  Total size - 4 (4bytes, 6 or 10), flags (2bytes), padding size (4bytes),
#    OptionalCRC.
#  Flags: (subject to unsyncronization)
#    %x0000000 00000000
#    x - CRC data present

#If  this flag is set four bytes of CRC-32 data is appended to the extended header. The CRC
#should  be calculated before unsynchronisation on the data between the extended header and
#the padding, i.e. the frames and only the frames.
#                              Total frame CRC   $xx xx xx xx

# v2.4: Total size (4bytes, unsync), length of flags (=1), flags, Optional part.
# 2.4 flags (with the corresponding "Optional part" format):
#      %0bcd0000
#    b - Tag is an update
#         Flag data length       $00
#    c - CRC data present
#         Flag data length       $05
#         Total frame CRC    5 * %0xxxxxxx
#    d - Tag restrictions
#         Flag data length       $01
#         Restrictions           %ppqrrstt

sub read_ext_header {	# XXXX in 2.3, it should be unsyncronized
    my $self = shift;
    my $ext_header = $self->{extheader};
    # flags, padding and crc ignored at this time
    my $size;
    if ($self->{major}==4) {
	$size = un_syncsafe_4bytes substr $ext_header, 0, 4;
    } else { # 4 bytes extra for the size field itself
	$size = 4 + unpack("N", $ext_header);
    }
    $self->{frame_start} += $size;
    return 1;
}

sub extract_data {	# Main sub for getting data from a frame
	my ($self, $data, $format, $noDecode, $arr) = @_;
	my ($rule, $found,$encoding, @result, $e);

	$encoding=0;
	$arr ||= 0;			# 1: values only; 2: return array
	foreach $rule (@$format) {
		next if exists $rule->{v3name};
		last if $rule->{optional} and not length $data;
		# get the data
		if ( exists $rule->{mlen} ) {	# minlength, data is string
			($found, $data) = ($data, "");	# Never with encoding
		} elsif ( $rule->{len} == 0 ) {	# Till \0
		  if (exists $rule->{encoded} && ($encoding =~ /^[12]$/)) {
		    ($found, $data) = ($data =~ /^((?:..)*?)(?:\0\0(.*)|\z)/s);
		  } else {
		    ($found, $data) = split /\x00/, $data, 2;
		  }
		} elsif ($rule->{len} == -1) {	# Till end
			($found, $data) = ($data, "");
		} else {
			$found = substr $data, 0,$rule->{len};
			substr ($data, 0,$rule->{len}) = '';
		}

		# was data found?
		unless (defined $found && $found ne "") {
			$found = "";
			$found = $rule->{default} if exists $rule->{default};
		}

		# work with data
		if ($rule->{name} eq "_encoding") {
			$encoding=unpack ("C", $found);
			push @result, 'encoding' unless $arr == 1;
			push @result, $encoding;
		} else {
			if (exists $rule->{encoded}) {	# decode data
			  if ( $encoding > 3 ) {
			    warn "Encoding type '$encoding' not supported: found in $rule->{name}\n";
			    next;
			  } elsif ($encoding and not $trustencoding) {
			    warn "UTF encoding types disabled via MP3TAG_DECODE_UNICODE): found in $rule->{name}\n";
			    next;
			  } elsif ($encoding) {
			    # 0 = latin1 (effectively: unknown)
			    # 1 = UTF-16 with BOM
			    # 2 = UTF-16be, no BOM
			    # 3 = UTF-8
			    require Encode;
			    if ($decode_utf8) {
			      $found = Encode::decode($dec_types[$encoding],
						      $found);
			    } elsif ($encoding < 3) {
			      # Reencode in UTF-8
			      $found = Encode::decode($dec_types[$encoding],
						      $found);
			      $found = Encode::encode('UTF-8', $found);
			    }
			  } elsif (not $noDecode and $e = $self->botched_encoding) {
			    require Encode;
			    $found = Encode::decode( $e, $found );
			  }
			}

			$found = toNumber($found) if $rule->{isnum};

			unless ($arr) {
			  $found = $rule->{func}->($found) if exists $rule->{func};

			  unless (exists $rule->{data} || !defined $found) {
				$found =~ s/[\x00]+$//;   # some progs pad text fields with \x00
				$found =~ s![\x00]! / !g; # some progs use \x00 inside a text string to seperate text strings
				$found =~ s/ +$//;        # no trailing spaces after the text
			  }

			  if (exists $rule->{re2}) {
				while (my ($pat, $rep) = each %{$rule->{re2}}) {
					$found =~ s/$pat/$rep/gis;
				}
			  }
			}
			# store data
			push @result, $rule->{name} unless $arr == 1;
			push @result, $found;
		}
	}
	return {@result} unless $arr;
	return \@result;
}

sub botched_encoding ($) {
    my($self) = @_;
    return if $self->{fixed_encoding};
    return unless my $enc = $self->get_config1('decode_encoding_v2');
    # Don't recourse into TXXX[*] (inside-[] is encoded,
    # and frame_select() reads ALL TXXX frames...)
    local $self->{fixed_encoding} = 1;
    return unless $self->get_config1('ignore_trusted_encoding0_v2')
	or not $self->frame_select('TXXX', 'trusted_encoding0_v2');
    $enc;
}

# Make editing in presence of decode_encoding_v2 more predictable:
sub frames_need_fix_encoding ($) {
    my($self) = @_;
    return unless $self->botched_encoding;
    my($fname, $rule, %fix);
    for $fname (keys %{$self->{frames}}) {
      my $frame = $self->{frames}->{$fname};
      next unless defined $frame;	# XXXX Needed?
      my $fname4 = substr ($fname, 0, 4);
      my($result, $e) = $frame->{data};
      my $format = get_format($fname4);
      next unless defined $format;
      foreach $rule (@$format) {
	next if exists $rule->{v3name};
	# Otherwise _encoding is the first entry
	last if $rule->{name} ne '_encoding';
	$e = unpack ("C", $result);
      }
      next unless defined $e and not $e;	# The unfortunate "latin1"
      my $txts     = $self->get_frame($fname, 'array_nokey');
      my $raw_txts = $self->get_frame($fname, 'array_nodecode');
      $fix{$fname} = $txts			# Really need to fix:
	if join("\0\0\0", @$txts) ne join("\0\0\0", @$raw_txts);
    }
    return unless %fix;
    \%fix;
}

sub fix_frames_encoding ($) {	# do not touch frames unless absolutely needed
    my($self) = @_;
    my($fix, $fname, $txt) = $self->frames_need_fix_encoding;
    while (($fname, $txt) = each %{$fix || {}}) {
      shift @$txt;	# The 1st field is always _encoding; recalculate it
      $self->change_frame($fname, @$txt) or die;
    }
    $self->{fixed_encoding} = 1;
    $self->frame_select('TXXX', 'trusted_encoding0_v2', undef, 1)
	if $self->get_config1('id3v2_set_trusted_encoding0');
    return($fix and keys %$fix);	# Better be scalar context...
}

#Searches for a format string for a specified frame. format strings exist for
#specific frames, or also for a group of frames. Specific format strings have
#precedence over general ones.

sub get_format {
    my $fname = shift;
    # to be quiet if called from supported_frames or what_data
    my $quiet = shift;
    my $fnamecopy = $fname;
    while ($fname ne "") {
	return $format{$fname} if exists $format{$fname};
	substr ($fname, -1) =""; #delete last char
    }
    warn "Unknown Frame-Format found: $fnamecopy\n" unless defined $quiet;
    return undef;
}

#Reads the flags of a frame, and returns a hash with all flags as keys, and 
#0/1 as value for unset/set.
sub check_flags {
    # how to detect unknown flags?
    my ($self, $flags)=@_;
    # %0abc0000 %0h00kmnp (this is byte1 byte2)
    my @flagmap4 = qw/data_length unsync encryption compression unknown_j unknown_i groupid 0
		      unknown_g unknown_f unknown_e unknown_d read_only file_preserv tag_preserv 0/;
    # %abc00000 %ijk00000
    my @flagmap3 = qw/unknown_o unknown_n unknown_l unknown_m unknown_l groupid encryption compression
		      unknown_h unknown_g unknown_f unknown_e unknown_d read_only file_preserv tag_preserv/;
    # flags were unpacked with 'n', so pack('v') gives byte2 byte1
    # unpack('b16') puts more significant bits to the right, separately for 
    # each byte; so the order is as specified above
# 2.4:
#     %0abc0000 %0h00kmnp (this is byte1 byte2)
#    a - Tag alter preservation
#    b - File alter preservation
#    c - Read only
#    h - Grouping identity
#    k - Compression
#    m - Encryption
#    n - Unsynchronisation
#    p - Data length indicator
# 2.3:
#     %abc00000 %ijk00000
#    a - Tag alter preservation
#    b - File alter preservation
#    c - Read only
#    i - Compression
#    j - Encryption
#    k - Grouping identity
    my @flagmap = $self->{major} == 4 ? @flagmap4 : @flagmap3;
    my %flags = map { (shift @flagmap) => $_ } split (//, unpack('b16',pack('v',$flags)));
    $flags{unchanged}=1;
    return \%flags;
}

sub build_flags {
    my %flags=@_;
    my $flags=0;
    my %flagmap=(groupid=>32, encryption=>64, compression=>128,
		 read_only=>8192, file_preserv=>16384, tag_preserv=>32768);
    while (my($flag,$set)=each %flags) {
	if ($set and exists $flagmap{$flag}) {
	    $flags += $flagmap{$flag};
	} elsif (not exists $flagmap{$flag}) {
	    warn "Unknown flag during tag write: $flag\n";
	}
    }
    return $flags;
}

sub DESTROY {
}


##################################
#
# How to store frame formats?
#
# format{fname}=[{xxx},{xxx},...]
#
# array containing descriptions of the different parts of a frame. Each description
# is a hash, which contains information, how to read the part.
#
# As Example: TCON
#     Text encoding                $xx
#     Information                  <text string according to encoding
#
# TCON consist of two parts, so a array with two hashes is needed to describe this frame.
#
# A hash may contain the following keys.
#
#          * len     - says how many bytes to read for this part. 0 means read until \x00, -1 means
#                      read until end of frame, any value > 0 specifies an exact length
#          * mlen    - specifies a minimum length for the data, real length is until end of frame
#			(we assume it is not paired with encoding)
#          * name    - the user sees this part of the frame under this name. If this part contains
#                      binary data, the name should start with a _
#                      The name "_encoding" is reserved for the encoding part of a frame, which
#                      is handled specifically to support encoding of text strings
#				(Is assumed to be the first entry, unless v3name)
#          * encoded - this part has to be encoded following to the encoding information
#          * func    - a reference to a sub, which is called after the data is extracted. It gets
#                      this data as argument and has to return some data, which is then returned
#                      a result of this part
#          * isnum=1 - indicator that field stores a number as binary number
#          * re2     - hash with information for a replace: s/key/value/
#                      This is used after a call of `func' when reading a frame
#          * re2b    - hash with information for a replace: s/key/value/
#                      This is used when adding a frame
#          * func_back - Translator function for add_frame (after re2b).
#          * data=1  - indicator that this part contains binary data
#          * default - default value, if data contains no information
#
# Name and exactly one of len or mlen are mandatory.
#
# TCON example:
# 
# $format{TCON}=[{len=> 1, name=>"encoding", data=>1},
#                {len=>-1, name=>"text", func=>\&TCON, re2=>{'\(RX\)'=>'Remix', '\(CR\)'=>'Cover'}] 
#
############################

sub toNumber {
  my $num = 0;
  $num = (256*$num)+unpack("C",$_) for split("",shift);

  return $num;
}

sub APIC {			# MAX about 20
    my $byte = shift;
    my $index = unpack ("C", $byte);
    my @pictypes = ("Other", "32x32 pixels 'file icon' (PNG only)", "Other file icon",
		    "Cover (front)", "Cover (back)", "Leaflet page",
		    "Media (e.g. label side of CD)", "Lead artist/lead performer/soloist",
		    "Artist/performer", "Conductor", "Band/Orchestra", "Composer",
		    "Lyricist/text writer", "Recording Location", "During recording",
		    "During performance", "Movie/video screen capture",
		    "A bright coloured fish", "Illustration", "Band/artist logotype",
		    "Publisher/Studio logotype");
    my $how = shift;
    if (defined $how) { # called by what_data
	die unless $how eq 1 and $byte eq 1;
	my $c=0;
	my %ret = map {$_, chr($c++)} @pictypes;
	return \%ret;
    }
    # called by extract_data
    return "Unknown...  Error?" if $index > $#pictypes;
    return $pictypes[$index];
}

sub COMR {			# MAX about 9
    my $data = shift;
    my $number = unpack ("C", $data);
    my @receivedas = ("Other","Standard CD album with other songs",
		      "Compressed audio on CD","File over the Internet",
		      "Stream over the Internet","As note sheets",
		      "As note sheets in a book with other sheets",
		      "Music on other media","Non-musical merchandise");
    my $how = shift;
    if (defined $how) {
	die unless $how eq 1 and $data eq 1;
	my $c=0;
	my %ret = map {$_, chr($c++)} @receivedas;
	return \%ret;
    }
    return $number if ($number>8);
    return $receivedas[$number];
}

sub PIC {
	# ID3v2.2 stores only 3 character Image format for pictures
	# and not mime type: Convert image format to mime type
	my $data = shift;

	my $how = shift;
	if (defined $how) { # called by what_data
		die unless $how eq 1 and $data eq 1;
		my %ret={};
		return \%ret;
	}
	# called by extract_data
	if ($data eq "-->") {
		warn "ID3v2.2 PIC frame with link not supported\n";
		$data = "text/plain";
	} else {
		$data = "image/".(lc $data);
	}
	return $data;
}

sub TCON {
    my $data = shift;
    my $how = shift;
    if (defined $how) { # called by what_data
	die unless $how eq 1 and $data eq 1;
	my $c=0;
	my %ret = map {$_, "(".$c++.")"} @{MP3::Tag::ID3v1::genres()};
	$ret{"_FREE"}=1;
	$ret{Remix}='(RX)';
	$ret{Cover}="(CR)";
	return \%ret;
    }    # called by extract_data
    join ' / ', MP3::Tag::Implemenation::_massage_genres($data);
}

sub TCON_back {
    my $data = shift;
    $data = join ' / ', map MP3::Tag::Implemenation::_massage_genres($_, 'prefer_num'),
       split ' / ', $data;
    $data =~ s[(?:(?<=\(\d\))|(?<=\(\d\d\d\))|(?<=\((?:RX|CV|\d\d)\))) / ][]ig;
    $data =~ s[ / (?=\((?:RX|CV|\d{1,3})\))][]ig;
    $data;
}

sub TFLT {
    my $text = shift;
    my $how = shift;
    if (defined $how) {	# called by what_data
	die unless $how eq 1 and $text eq 1;
	my %ret=("MPEG Audio"=>"MPG",
		 "MPEG Audio MPEG 1/2 layer I"=>"MPG /1",
		 "MPEG Audio MPEG 1/2 layer II"=>"MPG /2",
		 "MPEG Audio MPEG 1/2 layer III"=>"MPG /3",
		 "MPEG Audio MPEG 2.5"=>"MPG /2.5",
		 "Transform-domain Weighted Interleave Vector Quantization"=>"VQF",
		 "Pulse Code Modulated Audio"=>"PCM",
		 "Advanced audio compression"=>"AAC",
		 "_FREE"=>1,
		);
	return \%ret;
    }
    #called by extract_data
    return "" if $text eq "";
    $text =~ s/MPG/MPEG Audio/;
    $text =~ s/VQF/Transform-domain Weighted Interleave Vector Quantization/;
    $text =~ s/PCM/Pulse Code Modulated Audio/;
    $text =~ s/AAC/Advanced audio compression/;
    unless ($text =~ s!/1!MPEG 1/2 layer I!) {
	unless ($text =~ s!/2!MPEG 1/2 layer II!) {
	    unless ($text =~ s!/3!MPEG 1/2 layer III!) {
		$text =~ s!/2\.5!MPEG 2.5!;
	    }
	}
    }
    return $text;
}

sub TMED {
    #called by extract_data
    my $text = shift;
    return "" if $text eq "";
    if ($text =~ /(?<!\() \( ([\w\/]*) \) /x) {
	my $found = $1;
	if ($found =~ s!DIG!Other digital Media! || 
	    $found =~ /DAT/ ||
	    $found =~ /DCC/ ||
	    $found =~ /DVD/ ||
	    $found =~ s!MD!MiniDisc!  || 
	    $found =~ s!LD!Laserdisc!) {
	    $found =~ s!/A!, Analog Transfer from Audio!;
	}
	elsif ($found =~ /CD/) {
	    $found =~ s!/DD!, DDD!;
	    $found =~ s!/AD!, ADD!;
	    $found =~ s!/AA!, AAD!;
	}
	elsif ($found =~ s!ANA!Other analog Media!) {
	    $found =~ s!/WAC!, Wax cylinder!;
	    $found =~ s!/8CA!, 8-track tape cassette!;
	}
	elsif ($found =~ s!TT!Turntable records!) {
	    $found =~ s!/33!, 33.33 rpm!;
	    $found =~ s!/45!, 45 rpm!;
	    $found =~ s!/71!, 71.29 rpm!;
	    $found =~ s!/76!, 76.59 rpm!;
	    $found =~ s!/78!, 78.26 rpm!;
	    $found =~ s!/80!, 80 rpm!;
	}
	elsif ($found =~ s!TV!Television! ||
	       $found =~ s!VID!Video! ||
	       $found =~ s!RAD!Radio!) {
	    $found =~ s!/!, !;
	}
	elsif ($found =~ s!TEL!Telephone!) {
	    $found =~ s!/I!, ISDN!;
	}
	elsif ($found =~ s!REE!Reel! ||
	       $found =~ s!MC!MC (normal cassette)!) {
	    $found =~ s!/4!, 4.75 cm/s (normal speed for a two sided cassette)!;
	    $found =~ s!/9!, 9.5 cm/s!;
	    $found =~ s!/19!, 19 cm/s!;
	    $found =~ s!/38!, 38 cm/s!;
	    $found =~ s!/76!, 76 cm/s!;
	    $found =~ s!/I!, Type I cassette (ferric/normal)!;
	    $found =~ s!/II!, Type II cassette (chrome)!;
	    $found =~ s!/III!, Type III cassette (ferric chrome)!;
	    $found =~ s!/IV!, Type IV cassette (metal)!;
	}
	$text =~ s/(?<!\() \( ([\w\/]*) \)/$found/x;
    }
    $text =~ s/\(\(/\(/g;
    $text =~ s/  / /g;

    return $text;
}

for my $elt ( qw( cddb_id cdindex_id ) ) {
  no strict 'refs';
  *$elt = sub (;$) {
    my $self = shift;
    $self->frame_select('TXXX', $elt);
  }
}

BEGIN {
	# ID3v2.2, v2.3 are supported, v2.4 is very compatible...
	@supported_majors=(0,0,1,1,1);

	my $encoding    ={len=>1, name=>"_encoding", data=>1};
	my $text_enc    ={len=>-1, name=>"Text", encoded=>1};
	my $text        ={len=>-1, name=>"Text"};
	my $description ={len=>0, name=>"Description", encoded=>1};
	my $url         ={len=>-1, name=>"URL"};
	my $url0        ={len=>0,  name=>"URL"};
	my $data        ={len=>-1, name=>"_Data", data=>1};
	my $language    ={len=>3, name=>"Language"};

	# this list contains all id3v2.2 frame names which can be matched directly to a id3v2.3 frame
	%v2names_to_v3 = (
			  BUF => "RBUF",
			  CNT => "PCNT",
			  COM => "COMM",
			  CRA => "AENC",
			  EQU => "EQUA",
			  ETC => "ETCO",
			  GEO => "GEOB",
			  IPL => "IPLS",
			  MCI => "MDCI",
			  MLL => "MLLT",
			  POP => "POPM",
			  REV => "RVRB",
			  RVA => "RVAD",
			  SLT => "SYLT",
			  STC => "SYTC",
			  TFT => "TFLT",
			  TMT => "TMED",
			  UFI => "UFID",
			  ULT => "USLT",
			  TAL => "TALB",
			  TBP => "TBPM",
			  TCM => "TCOM",
			  TCO => "TCON",
			  TCR => "TCOP",
			  TDA => "TDAT",
			  TDY => "TDLY",
			  TEN => "TENC",
			  TIM => "TIME",
			  TKE => "TKEY",
			  TLA => "TLAN",
			  TLE => "TLEN",
			  TOA => "TOPE",
			  TOF => "TOFN",
			  TOL => "TOLY",
			  TOR => "TORY",
			  TOT => "TOAL",
			  TP1 => "TPE1",
			  TP2 => "TPE2",
			  TP3 => "TPE3",
			  TP4 => "TPE4",
			  TPA => "TPOS",
			  TPB => "TPUB",
			  TRC => "TSRC",
			  TRD => "TRDA",
			  TRK => "TRCK",
			  TSI => "TSIZ",
			  TSS => "TSSE",
			  TT1 => "TIT1",
			  TT2 => "TIT2",
			  TT3 => "TIT3",
			  TXT => "TEXT",
			  TXX => "TXXX",
			  TYE => "TYER",
			  WAF => "WOAF",
			  WAR => "WOAR",
			  WAS => "WOAS",
			  WCM => "WCOM",
			  WCP => "WCOP",
			  WPB => "WPUB",
			  WXX => "WXXX",
			 );

	%format = (
		   AENC => [$url0, {len=>2, name=>"Preview start", isnum=>1},
			    {len=>2, name=>"Preview length", isnum=>1}, $data],
		   APIC => [$encoding, {len=>0, name=>"MIME type"},
			    {len=>1, name=>"Picture Type", small_max=>1, func=>\&APIC},
			    $description, $data],
		   COMM => [$encoding, $language, $description, $text_enc],
		   COMR => [$encoding, {len=>0, name=>"Price"},
			    {len=>8, name=>"Valid until"}, $url0,
			    {len=>1, name=>"Received as", small_max=>1, func=>\&COMR},
			    {len=>0, name=>"Name of Seller", encoded=>1},
			    $description, {len=>0, name=>"MIME type", optional=>1},
			    {len=>-1, name=>"_Logo", data=>1, optional => 1}],
		   CRM  => [{v3name=>""},{len=>0, name=>"Owner ID"}, {len=>0, name=>"Content/explanation"}, $data], #v2.2
		   ENCR => [{len=>0, name=>"Owner ID"}, {len=>0, name=>"Method symbol"}, $data],
		   #EQUA => [],
		   #ETCO => [],
		   GEOB  => [$encoding, {len=>0, name=>"MIME type"},
			     {len=>0, name=>"Filename"}, $description, $data],
		   GRID => [{len=>0, name=>"Owner"}, {len=>1, name=>"Symbol", isnum=>1},
			    $data],
		   IPLS => [$encoding, $text_enc],	# in 2.4 split into TMCL, TIPL
		   LNK  => [{len=>4, name=>"ID", func=>\&LNK}, {len=>0, name=>"URL"}, $text],
		   LINK => [{len=>4, name=>"ID"}, {len=>0, name=>"URL"}, $text],
		   MCDI => [$data],
		   #MLLT  => [],
		   OWNE => [$encoding, {len=>0, name=>"Price payed"},
			    {len=>0, name=>"Date of purchase"}, $text_enc],
		   PCNT => [{mlen=>4, name=>"Text", isnum=>1}],
		   PIC  => [{v3name => "APIC"}, $encoding, {len=>3, name=>"Image Format", func=>\&PIC},
			    {len=>1, name=>"Picture Type", func=>\&APIC}, $description, $data], #v2.2
		   POPM  => [{len=>0, name=>"URL"},{len=>1, name=>"Rating", isnum=>1},
			     {mlen=>4, name=>"Counter", isnum=>1, optional=>1}],
		   #POSS => [],
		   PRIV => [{len=>0, name=>"Text"}, $data],
		   RBUF => [{len=>3, name=>"Buffer size", isnum=>1},
			    {len=>1, name=>"Embedded info flag", isnum=>1},
			    {len=>4, name=>"Offset to next tag", isnum=>1, optional=>1}],
		   #RVAD => [],
		   RVRB => [{len=>2, name=>"Reverb left (ms)", isnum=>1},
			    {len=>2, name=>"Reverb right (ms)", isnum=>1},
			    {len=>1, name=>"Reverb bounces (left)", isnum=>1},
			    {len=>1, name=>"Reverb bounces (right)", isnum=>1},
			    {len=>1, name=>"Reverb feedback (left to left)", isnum=>1},
			    {len=>1, name=>"Reverb feedback (left to right)", isnum=>1},
			    {len=>1, name=>"Reverb feedback (right to right)", isnum=>1},
			    {len=>1, name=>"Reverb feedback (right to left)", isnum=>1},
			    {len=>1, name=>"Premix left to right", isnum=>1},
			    {len=>1, name=>"Premix right to left", isnum=>1},],
		   SYTC => [{len=>1, name=>"Time Stamp Format", isnum=>1}, $data],
		   #SYLT => [],
		   T    => [$encoding, $text_enc],
		   TCON => [$encoding,
			    {%$text_enc, func=>\&TCON, func_back => \&TCON_back,
			     re2=>{'\(RX\)'=>'Remix', '\(CR\)'=>'Cover'},
			     # re2b=>{'\bRemix\b'=>'(RX)', '\bCover\b'=>'(CR)'}
			    }],
		   TCOP => [$encoding,
			    {%$text_enc, re2 => {'^(?!\Z)'=>'(C) '},
			     re2b => {'^(Copyright\b)?\s*(\(C\)\s*)?' => ''}}],
		   # TDRC => [$encoding, $text_enc, data => 1],
		   TFLT => [$encoding, {%$text_enc, func=>\&TFLT}],
		   TIPL => [{v3name => "IPLS"}, $encoding, $text_enc],
		   TMCL => [{v3name => "IPLS"}, $encoding, $text_enc],
		   TMED => [$encoding, {%$text_enc, func=>\&TMED}], # no what_data support
		   TXXX => [$encoding, $description, $text_enc],
		   UFID => [{%$description, name=>"Text"}, $data],
		   USER => [$encoding, $language, $text_enc],
		   USLT => [$encoding, $language, $description, $text_enc],
		   W    => [$url],
		   WXXX => [$encoding, $description, $url],
	      );

    %long_names = (
		   AENC => "Audio encryption",
		   APIC => "Attached picture",
		   COMM => "Comments",
		   COMR => "Commercial frame",
		   ENCR => "Encryption method registration",
		   EQUA => "Equalization",
		   ETCO => "Event timing codes",
		   GEOB => "General encapsulated object",
		   GRID => "Group identification registration",
		   IPLS => "Involved people list",
		   LINK => "Linked information",
		   MCDI => "Music CD identifier",
		   MLLT => "MPEG location lookup table",
		   OWNE => "Ownership frame",
		   PRIV => "Private frame",
		   PCNT => "Play counter",
		   POPM => "Popularimeter",
		   POSS => "Position synchronisation frame",
		   RBUF => "Recommended buffer size",
		   RVAD => "Relative volume adjustment",
		   RVRB => "Reverb",
		   SYLT => "Synchronized lyric/text",
		   SYTC => "Synchronized tempo codes",
		   TALB => "Album/Movie/Show title",
		   TBPM => "BPM (beats per minute)",
		   TCOM => "Composer",
		   TCON => "Content type",
		   TCOP => "Copyright message",
		   TDAT => "Date",
		   TDLY => "Playlist delay",
		   TDRC => "Recording time",
		   TENC => "Encoded by",
		   TEXT => "Lyricist/Text writer",
		   TFLT => "File type",
		   TIME => "Time",
		   TIPL => "Involved people list",
		   TIT1 => "Content group description",
		   TIT2 => "Title/songname/content description",
		   TIT3 => "Subtitle/Description refinement",
		   TKEY => "Initial key",
		   TLAN => "Language(s)",
		   TLEN => "Length",
		   TMCL => "Musician credits list",
		   TMED => "Media type",
		   TOAL => "Original album/movie/show title",
		   TOFN => "Original filename",
		   TOLY => "Original lyricist(s)/text writer(s)",
		   TOPE => "Original artist(s)/performer(s)",
		   TORY => "Original release year",
		   TOWN => "File owner/licensee",
		   TPE1 => "Lead performer(s)/Soloist(s)",
		   TPE2 => "Band/orchestra/accompaniment",
		   TPE3 => "Conductor/performer refinement",
		   TPE4 => "Interpreted, remixed, or otherwise modified by",
		   TPOS => "Part of a set",
		   TPUB => "Publisher",
		   TRCK => "Track number/Position in set",
		   TRDA => "Recording dates",
		   TRSN => "Internet radio station name",
		   TRSO => "Internet radio station owner",
		   TSIZ => "Size",
		   TSRC => "ISRC (international standard recording code)",
		   TSSE => "Software/Hardware and settings used for encoding",
		   TYER => "Year",
		   TXXX => "User defined text information frame",
		   UFID => "Unique file identifier",
		   USER => "Terms of use",
		   USLT => "Unsychronized lyric/text transcription",
		   WCOM => "Commercial information",
		   WCOP => "Copyright/Legal information",
		   WOAF => "Official audio file webpage",
		   WOAR => "Official artist/performer webpage",
		   WOAS => "Official audio source webpage",
		   WORS => "Official internet radio station homepage",
		   WPAY => "Payment",
		   WPUB => "Publishers official webpage",
		   WXXX => "User defined URL link frame",

		   # ID3v2.2 frames which cannot linked directly to a ID3v2.3 frame
		   CRM => "Encrypted meta frame",
		   PIC => "Attached picture",
		   LNK => "Linked information",
		  );

	# these fields have restricted input (FRAMEfield)
	%res_inp=( "APICPicture Type" => \&APIC,
		   "TCONText" => \&TCON, # Actually, has func_back()...
		   "TFLTText" => \&TFLT,
		   "COMRReceived as" => \&COMR,
		 );
	# have small_max
	%is_small_int = ("APICPicture Type" => 1, "COMRReceived as" => 1);

        for my $k (keys %res_inp) {
	  my %h = %{ $field_map{$k} = $res_inp{$k}->(1,1) }; # Assign+make copy
	  delete $h{_FREE};
	  %h = reverse %h;
	  $field_map_back{$k} = \%h;
	}
	# Watch for 'lable':
	$field_map{'APICPicture Type'}{'Media (e.g. lable side of CD)'} =
	  $field_map{'APICPicture Type'}{'Media (e.g. label side of CD)'};
	%back_splt = qw(POPM 1); # Have numbers at end
	%embedded_Descr = qw(GEOD 1 COMR 1); # Have descr which is not leading
}

=pod

=back

=head1 BUGS

Writing C<v2.4>-layout tags is not supported.

Additionally, one should keep in mind that C<v2.3> and C<v2.4> have differences
in two areas:

=over 4

=item *

layout of information in the byte stream (in other words, in a file
considered as a string) is different;

=item *

semantic of frames is extended in C<v2.4> - more frames are defined, and
more frame flags are defined too.

=back

MP3::Tag does not even try to I<write> frames in C<v2.4>-layout.  However,
when I<reading> the frames, MP3::Tag does not assume any restriction on
the semantic of frames - it allows all the semantical extensions
defined in C<v2.4> even for C<v2.3> (and, probably, for C<v2.2>) layout.

C<[*]> (I expect, any sane program would do the same...)

Likewise, when writing frames, there is no restriction imposed on semantic.
If user specifies a frame the meaning of which is defined only in C<v2.4>,
we would happily write it even when we use C<v2.3> layout.  Same for frame
flags.  (And given the assumption C<[*]>, this is a correct thing to do...)

=head1 SEE ALSO

L<MP3::Tag>, L<MP3::Tag::ID3v1>, L<MP3::Tag::ID3v2_Data>

ID3v2 standard - http://www.id3.org
L<http://www.id3.org/id3v2-00>, L<http://www.id3.org/d3v2.3.0>,
L<http://www.id3.org/id3v2.4.0-structure>,
L<http://www.id3.org/id3v2.4.0-frames>,
L<http://id3lib.sourceforge.net/id3/id3v2.4.0-changes.txt>.

=head1 COPYRIGHT

Copyright (c) 2000-2008 Thomas Geffert, Ilya Zakharevich.  All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.

=cut


1;
