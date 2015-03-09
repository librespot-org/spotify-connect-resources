=head1 NAME

AnyEvent::IO::IOAIO - AnyEvent::IO backend based on IO::AIO

=head1 SYNOPSIS

   use AnyEvent::IO;

=head1 DESCRIPTION

This is the L<IO::AIO>-based backend of L<AnyEvent::IO> (via
L<AnyEvent::AIO>). All I/O operations it implements are done
asynchronously.

=head1 FUNCTIONS

=over 4

=cut

package AnyEvent::IO::IOAIO;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
our $VERSION = $AnyEvent::VERSION;

package AnyEvent::IO;

use IO::AIO 4.13 ();
use AnyEvent::AIO ();

our $MODEL = "AnyEvent::IO::IOAIO";

sub aio_load($$) {
   my ($cb, $data) = $_[1];
   IO::AIO::aio_load $_[0], $data,                  sub { $cb->($_[0] >= 0 ? $data : ()) };
}

sub aio_open($$$$) {
   my $cb = $_[3];
   IO::AIO::aio_open $_[0], $_[1], $_[2],           sub { $cb->($_[0] or ()) };
}

sub aio_close($$) {
   my $cb = $_[1];
   IO::AIO::aio_close $_[0],                        sub { $cb->($_[0] >= 0 ? 1 : ()) };
}

sub aio_seek($$$$) {
   my ($cb) = $_[3];
   IO::AIO::aio_seek $_[0], $_[1], $_[2],           sub { $cb->($_[0] >= 0 ? $_[0] : ()) };
}

sub aio_read($$$) {
   my ($cb, $data) = $_[2];
   IO::AIO::aio_read $_[0], undef, $_[1], $data, 0, sub { $cb->($_[0] >= 0 ? $data : ()) };
}

sub aio_write($$$) {
   my $cb = $_[2];
   IO::AIO::aio_write $_[0], undef, (length $_[1]), $_[1], 0,
                                                    sub { $cb->($_[0] >= 0 ? $_[0] : ()) };
}

sub aio_truncate($$$) {
   my $cb = $_[2];
   IO::AIO::aio_truncate $_[0], $_[1],              sub { $cb->($_[0] ? () : 1) };
}

sub aio_utime($$$$) {
   my $cb = $_[3];
   IO::AIO::aio_utime $_[0], $_[1], $_[2],          sub { $cb->($_[0] ? () : 1) };
}

sub aio_chown($$$$) {
   my $cb = $_[3];
   IO::AIO::aio_chown $_[0], $_[1], $_[2],          sub { $cb->($_[0] ? () : 1) };
}

sub aio_chmod($$$) {
   my $cb = $_[2];
   IO::AIO::aio_chmod $_[0], $_[1],                 sub { $cb->($_[0] ? () : 1) };
}

sub aio_stat($$) {
   my $cb = $_[1];
   IO::AIO::aio_stat $_[0],                         sub { $cb->($_[0] ? () : 1) };
}

sub aio_lstat($$) {
   my $cb = $_[1];
   IO::AIO::aio_lstat $_[0],                        sub { $cb->($_[0] ? () : 1) }
}

sub aio_link($$$) {
   my $cb = $_[2];
   IO::AIO::aio_link $_[0], $_[1],                  sub { $cb->($_[0] ? () : 1) };
}

sub aio_symlink($$$) {
   my $cb = $_[2];
   IO::AIO::aio_symlink $_[0], $_[1],               sub { $cb->($_[0] ? () : 1) };
}

sub aio_readlink($$) {
   my $cb = $_[1];
   IO::AIO::aio_readlink $_[0],                     sub { $cb->(defined $_[0] ? $_[0] : ()) };
}

sub aio_rename($$$) {
   my $cb = $_[2];
   IO::AIO::aio_rename $_[0], $_[1],                sub { $cb->($_[0] ? () : 1) };
}

sub aio_unlink($$) {
   my $cb = $_[1];
   IO::AIO::aio_unlink $_[0],                       sub { $cb->($_[0] ? () : 1) };
}

sub aio_mkdir($$$) {
   my $cb = $_[2];
   IO::AIO::aio_mkdir $_[0], $_[1],                 sub { $cb->($_[0] ? () : 1) };
}

sub aio_rmdir($$) {
   my $cb = $_[1];
   IO::AIO::aio_rmdir $_[0],                        sub { $cb->($_[0] ? () : 1) };
}

sub aio_readdir($$) {
   my $cb = $_[1];

   IO::AIO::aio_readdirx $_[0], IO::AIO::READDIR_DIRS_FIRST | IO::AIO::READDIR_STAT_ORDER,
                                                    sub { $cb->($_[0] or ()); };
}

=back

=head1 SEE ALSO

L<AnyEvent::IO>, L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

