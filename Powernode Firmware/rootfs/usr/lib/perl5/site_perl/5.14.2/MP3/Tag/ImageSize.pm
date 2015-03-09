package MP3::Tag::ImageSize;

use strict;
use File::Basename;
#use File::Spec;
use vars qw /$VERSION @ISA/;

$VERSION="0.01";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::ImageSize - extract size info from image files via L<Image::Size|Image::Size>.

=head1 SYNOPSIS

  my $db = MP3::Tag::ImageSize->new($filename);	# Name of multimedia file

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::ImageSize is designed to be called from the MP3::Tag module.

It implements width(), height() and mime_type() methods (sizes in pixels).

They return C<undef> if C<Image::Size> is not available, or does not return valid data.

=head1 SEE ALSO

L<Image::Size>, L<MP3::Tag>

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

my @fields = qw( 0 0 width height img_type mime_type );
for my $elt ( 2, 3, 4, 5 ) {	#  i_bitdepth
  my $r = sub (;$) {
    my $self = shift;
    unless ($self->[1]) {
	my ($w, $h, $t) = eval { require Image::Size;
				 Image::Size::imgsize($self->[0]) };
	defined $w or @$self[1..4] = (1,undef,undef,undef), return;
	my $tt = "image/\L$t";
	@$self[1..5] = (1, $w, $h, $t, $tt);
    }
    return $self->[$elt];
  };
  no strict 'refs';
  *{$fields[$elt]} = $r;
}

for my $elt ( qw( title track artist album year genre comment ) ) {
  no strict 'refs';
  *$elt = sub (;$) { return };
}

1;
