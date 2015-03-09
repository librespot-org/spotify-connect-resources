package MP3::Tag::LastResort;

use strict;
use vars qw /$VERSION @ISA/;

$VERSION="1.00";
@ISA = 'MP3::Tag::__hasparent';

=pod

=head1 NAME

MP3::Tag::LastResort - Module for using other fields to fill autoinfo fields.

=head1 SYNOPSIS

  my $mp3extra = MP3::Tag::LastResort::new_with_parent($filename, $parent);
  $comment = $mp3inf->comment();

see L<MP3::Tag>

=head1 DESCRIPTION

MP3::Tag::LastResort is designed to be called from the MP3::Tag module.

It uses the artist_collection() as comment() if comment() is not otherwise
defined.

=cut


# Constructor

sub new_with_parent {
    my ($class, $filename, $parent) = @_;
    bless {parent => $parent}, $class;
}

# Destructor

sub DESTROY {}

for my $elt ( qw( title track artist album year genre ) ) {
  no strict 'refs';
  *$elt = sub (;$) { return };
}

sub comment {
  shift->{parent}->artist_collection()
}

1;
