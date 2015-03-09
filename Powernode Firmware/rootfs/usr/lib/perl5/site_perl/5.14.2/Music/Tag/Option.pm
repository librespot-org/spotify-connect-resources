package Music::Tag::Option;
use strict; use warnings; use utf8;
our $VERSION = '.4101';
use base qw(Music::Tag::Generic);

# Copyright © 2006,2010 Edward Allen III. Some rights reserved.

#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the README file.
#



sub set_tag {
    my $self = shift;
    my $okmethods = { map { lc($_) => 1 } @{ $self->info->datamethods } };
    while ( my ( $k, $v ) = each %{ $self->options } ) {
        if ( ( defined $v ) and ( $okmethods->{ lc($k) } ) ) {
            my $method = lc($k);
            $self->info->set_data($method,$v);
            $self->tagchange($method);
        }
    }
}

sub get_tag { goto &set_tag; }

1;
__END__
=pod

=head1 NAME

Music::Tag::Option - Plugin module for Music::Tag to set tags via tag optons 

=head1 SYNOPSIS

	use Music::Tag

	my $filename = "/var/lib/music/artist/album/track.flac";

	my $info = Music::Tag->new($filename, { quiet => 1 }, "ogg");

	$info->add_plugin(option, { artist => "Sarah Slean" });

	$info->get_info();
	   
	print "Artist is ", $info->artist;

	#Outputs "Artist is Sarah Slean"

=head1 DESCRIPTION

Music::Tag::Option is a plugin to set tags via the plugin option.

=head1 REQUIRED VALUES

None.

=head1 SET VALUES

=over 4

=item Any value you would like can be set this way.

=back

=head1 OPTIONS

Any tag accepted by L<Music::Tag>.

=head1 METHODS

=over

=item default_options

Returns the default options for the plugin.  

=item set_tag

Sets the info in the Music::Tag file to info from options.

=item get_tag

Same as set_tag.

=back

=head1 BUGS

No known additional bugs provided by this Module.

=head1 SEE ALSO

L<Music::Tag>

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

Copyright © 2007,2010 Edward Allen III. Some rights reserved.

