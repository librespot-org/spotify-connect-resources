package MP3::Tag::ImageExifTool;

use strict;
use File::Basename;
#use File::Spec;
use vars qw /$VERSION @ISA/;

$VERSION="0.01";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::ImageExifTool - extract size info from image files via L<Image::Size|Image::Size>.

=head1 SYNOPSIS

  my $db = MP3::Tag::ImageExifTool->new($filename);	# Name of multimedia file

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::ImageExifTool is designed to be called from the MP3::Tag module.

It implements width(), height() and mime_type() methods (sizes in pixels).

They return C<undef> if C<Image::Size> is not available, or does not return valid data.

=cut


# Constructor

sub new_with_parent {
    my ($class, $f, $p, $e, %seen, @cue) = (shift, shift, shift);
    $f = $f->filename if ref $f;
    bless [$f], $class;
}

sub new {
    my ($class, $f) = (shift, shift);
    $class->new_with_parent($f, undef, @_);
}

# Destructor

sub DESTROY {}

sub __info ($) {
  my $self = shift;
  unless (defined $self->[1]) {
      my $v = eval { require Image::ExifTool;
                     Image::ExifTool->new()->ImageInfo($self->[0], '-id3:*') };
      # How to detect errors?
      $self->[1] = $v->{Error} ? '' : $v;
  }
  return $self->[1];
}

my %tr = qw( mime_type MIMEType year Date width ImageWidth height ImageHeight
	     bit_depth BitDepth );

for my $elt ( qw( title track artist album year genre comment mime_type
		  width height ) ) {
  my $n = ($tr{$elt} or ucfirst $elt);
  my $is_genre = ($elt eq 'genre');
  my $r = sub ($) {
    my $info = shift()->__info;
    return unless $info;
    my $v = $info->{$n};
    $v =~ s/^None$// if $is_genre and $v;
    return $v;
  };
  no strict 'refs';
  *$elt = $r;
}

sub bit_depth ($) {
  my $info = shift()->__info;
  return unless $info;
  $info->{BitsPerSample} || $info->{Depth} || $info->{BitDepth}
}

sub field ($$) {
  my $info = shift()->__info;
  return unless $info;
  $info->{shift()}
}

sub _duration ($) {
  my $info = shift()->__info;
  return unless $info;
  my($d, $dd) = $info->{Duration};
  if (defined $d and $d =~ /\d/) {
    $dd = 1;
    return $d if $d =~ /^\d*(\.\d*)?$/;
  }
  # Probably this is already covered by Duration?  No, it is usually rounded...
  my($c, $r, $r1) = map $info->{$_}, qw(FrameCount VideoFrameRate FrameRate);
  unless (defined $c and $r ||= $r1) {	# $d usually contains rounded value
    return $1*3600 + $2*60 + $3 if $dd and $d =~ /^(\d+):(\d+):(\d+(\.\d*)?)$/;
    return $1*60 + $2 if $dd and $d =~ /^(\d+):(\d+(\.\d*)?)$/;
    return;
  }
  $r = 30/1.001 if $r =~ /^29.97\d*^/;
  $r = 24/1.001 if $r =~ /^23.9(7\d*|8)$/;
  $c/$r
}

sub img_type ($) {
  my $self = shift;
  my $t = $self->mime_type;
  return uc $1 if $t =~ m(^image/(.*));
  return;
}

1;
