package Music::Tag::Auto;
use strict; use warnings; use utf8;

our $VERSION = '.4101';
use base qw(Music::Tag::Generic);

# Copyright © 2006 Edward Allen III. Some rights reserved.

#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the README file.
#

sub default_options {
	{
		autoplugin => {
			mp3	=> "MP3",
			m4a => "M4A",
			m4p => "M4A",
			mp4 => "M4A",
			m4b => "M4A",
			'3gp' => "M4A",
			ogg => "OGG",
			flac => "FLAC"
		}
	}
}

sub new {
    my $class   = shift;
    my $parent  = shift;
    my $options = shift || {};
    my $self    = {};
    bless $self, $class;
    $self->info($parent);
    $self->options($options);
    my $plugin   = "";
    if ( $self->info->get_data('filename') =~ /\.([^\.]*)$/ ) {
		if (exists $self->options->{autoplugin}->{lc($1)}) {
		   $plugin = $self->options->{autoplugin}->{lc($1)}; 
		}
    }
	if (($plugin) && ($self->info->available_plugins($plugin))) {
		unless ( $plugin =~ /::/ ) {
			$plugin = "Music::Tag::" . $plugin;
		}
		$self->status(1, "Auto loading plugin: $plugin");
        my $type = lc($plugin);
        $type =~ s/^.*:://;
        $self->status(2, "Adding filetype: $plugin");
        $self->info->set_data('filetype',$type);
		if($self->info->_has_module($plugin)) {
			return $plugin->new( $self->info, $self->options );
		}
    }
    else {
        $self->error("Sorry, I can't find a plugin for ", $self->info->get_data('filename'));
        return undef;
    }
}

1;
__END__
=pod

=head1 NAME

Music::Tag::Auto - Plugin module for Music::Tag to load other plugins by file extension.

=head1 SYNOPSIS

	use Music::Tag

	my $filename = "/var/lib/music/artist/album/track.flac";

	my $info = Music::Tag->new($filename, { quiet => 1 }, "Auto");

	$info->get_info();
	print "Artist is ", $info->artist;


=head1 DESCRIPTION

Music::Tag::Auto is loaded automatically in Music::Tag .3 and newer to load other plugins.

=head1 REQUIRED VALUES

None.

=head1 SET VALUES

None.

=head1 OPTIONS

=over 4

=item B<autoplugin>

Option is a hash reference.  Reference maps file extensions to plugins. Default is: 

    {   mp3	  => "MP3",
        m4a   => "M4A",
        m4p   => "M4A",
        mp4   => "M4A",
        m4b   => "M4A",
        '3gp' => "M4A",
        ogg   => "OGG",
        flac  => "FLAC"   }

=back

=head1 METHODS

=over

=item new($parent, $options)

Returns a Music::Tag object based on file extension, if available.  Otherwise returns undef. 

=item default_options

Returns the default options for the plugin.  

=item set_tag

Not defined for this plugin.

=item get_tag

Not defined for this plugin.

=back

=head1 BUGS

No known additional bugs provided by this Module.

=head1 SEE ALSO

L<Music::Tag>, L<Music::Tag::FLAC>, L<Music::Tag::Lyrics>, L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::OGG>

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

Copyright © 2007 Edward Allen III. Some rights reserved.



