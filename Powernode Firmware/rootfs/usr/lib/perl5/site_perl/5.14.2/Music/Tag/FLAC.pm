package Music::Tag::FLAC;
use strict; use warnings; use utf8;
our $VERSION = '0.4101';

# Copyright © 2007,2010 Edward Allen III. Some rights reserved.
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the README file.

use Audio::FLAC::Header;
use base qw(Music::Tag::Generic);

sub flac {
	my $self = shift;
	unless ((exists $self->{_Flac}) && (ref $self->{_Flac})) {
		if ($self->info->has_data('filename')) {
			$self->{_Flac} = Audio::FLAC::Header->new($self->info->get_data('filename'));
		}
	}
	return $self->{_Flac};
}

our %tagmap = (
	TITLE	=> 'title',
	TRACKNUMBER => 'track',
	TRACKTOTAL => 'totaltracks',
	ARTIST => 'artist',
	ALBUM => 'album',
	COMMENT => 'comment',
	DATE => 'releasedate',
	GENRE => 'genre',
	DISC => 'disc',
	LABEL => 'label',
	ASIN => 'asin',
    MUSICBRAINZ_ARTISTID => 'mb_artistid',
    MUSICBRAINZ_ALBUMID => 'mb_albumid',
    MUSICBRAINZ_TRACKID => 'mb_trackid',
    MUSICBRAINZ_SORTNAME => 'sortname',
    RELEASECOUNTRY => 'countrycode',
    MUSICIP_PUID => 'mip_puid',
    MUSICBRAINZ_ALBUMARTIST => 'albumartist'
);

sub set_values {
	return ( values %tagmap, 'picture');
}

sub saved_values {
	return ( values %tagmap);
}
 
sub get_tag {
    my $self     = shift;
    if ( $self->flac ) {
		while (my ($t, $v) = each %{$self->flac->tags}) {
			if ((exists $tagmap{$t}) && (defined $v)) {
				my $method = $tagmap{$t};
				$self->info->set_data($method,$v);
			}
		}
        $self->info->set_data('secs', $self->flac->{trackTotalLengthSeconds} );
        $self->info->set_data('bitrate', int($self->flac->{bitRate} / 1000) );

		#"MIME type"     => The MIME Type of the picture encoding
		#"Picture Type"  => What the picture is off.  Usually set to 'Cover (front)'
		#"Description"   => A short description of the picture
		#"_Data"	       => The binary data for the picture.
        if (( $self->flac->picture) && ( not $self->info->has_data('picture'))) {
			my $pic = $self->flac->picture;
            $self->info->set_data('picture', {
					"MIME type" => $pic->{mimeType},
					"Picture Type" => $pic->{description},
					"_Data"	=> $pic->{imageData},
				});
        }
    }
    return $self;
}

sub set_tag {
    my $self = shift;
    if ( $self->flac ) {
		while (my ($t, $v) = each %tagmap) {
			if ($self->info->has_data($v)) {
				$self->flac->tags->{$t} = $self->info->get_data($v);
			}
		}
        $self->flac->write();
    }
    return $self;
}

sub close {
	my $self = shift;
    $self->{_Flac} = undef;
	delete $self->{_Flac};
}

sub default_options {
   {
   	wav_out_system => [ "flac", "-cd", "-c", "[FILENAME]" ],
   }
}

1;

# vim: tabstop=4
__END__
=pod

=for changes stop

=head1 NAME

Music::Tag::FLAC - Plugin module for Music::Tag to get information from flac headers. 

=for readme stop

=head1 SYNOPSIS

	use Music::Tag

	my $filename = "/var/lib/music/artist/album/track.flac";

	my $info = Music::Tag->new($filename, { quiet => 1 }, "FLAC");

	$info->get_info();
	   
	print "Artist is ", $info->artist;

=for readme continue

=head1 DESCRIPTION

Music::Tag::FLAC is used to read flac header information. It uses Audio::FLAC::Header. 

=begin readme

=head1 INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

=head1 DEPENDENCIES

This module requires these other modules and libraries:

   Music::Tag
   Audio::FLAC::Header

The version info in the Makefile is based on what I use.  You can get 
away with older versions in many cases. Do not install an older version
of MP3::Tag.

=head1 TEST FILES

Test files for this module are based on the sample file for Audio::M4P.  For testing only.

=end readme

=for readme stop

=head1 REQUIRED DATA VALUES

No values are required (except filename, which is usually provided on object creation). 

=head1 SET DATA VALUES

=over 4

=item title, track, totaltracks, artist, album, comment, releasedate, genre, disc, label

Uses standard tags for these

=item asin

Uses custom tag "ASIN" for this

=item mb_artistid, mb_albumid, mb_trackid, mip_puid, countrycode, albumartist

Uses MusicBrainz recommended tags for these.

=item secs, bitrate

Gathers this info from file.  Please note that secs is fractional.

=pod

=item picture

This is currently read-only.

=back

=head1 OPTIONS

None currently.

=head1 METHODS

=over 4

=item B<default_options()>

Returns the default options for the plugin.  

=item B<set_tag()>

Save object back to FLAC header.

=item B<get_tag()>

Load information from FLAC header.

=item B<set_values>

A list of values that can be set by this module.

=item B<saved_values>

A list of values that can be saved by this module.

=item B<close()>

Close the file and destroy the Audio::FLAC::Header

=item flac

Returns the Audio::FLAC::Header object

=back

=head1 BUGS

Plugin does not fully support all fields I would like.  Pictures are read only (limitation of Audio::FLAC::Header).

Please use github for bug tracking: L<http://github.com/riemann42/Music-Tag-FLAC/issues|http://github.com/riemann42/Music-Tag-FLAC/issues>.

=head1 SEE ALSO 

L<Audio::FLAC::Header>, L<Music::Tag>, L<Music::Tag::Amazon>, L<Music::Tag::File>, L<Music::Tag::Lyrics>,
L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::MusicBrainz>, L<Music::Tag::OGG>, L<Music::Tag::Option>

=head1 SOURCE

Source is available at github: L<http://github.com/riemann42/Music-Tag-FLAC|http://github.com/riemann42/Music-Tag-FLAC>.

=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either:

a) the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

b) the "Artistic License" which comes with Perl.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either
the GNU General Public License or the Artistic License for more details.

You should have received a copy of the Artistic License with this
Kit, in the file named "Artistic".  If not, I'll be glad to provide one.

You should also have received a copy of the GNU General Public License
along with this program in the file named "Copying". If not, write to the
Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA or visit their web page on the Internet at
http://www.gnu.org/copyleft/gpl.html.


=head1 COPYRIGHT

Copyright © 2007,2008,2010 Edward Allen III. Some rights reserved.

