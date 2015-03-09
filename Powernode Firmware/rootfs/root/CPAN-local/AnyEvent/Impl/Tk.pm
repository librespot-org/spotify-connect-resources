=head1 NAME

AnyEvent::Impl::Tk - AnyEvent adaptor for Tk

=head1 SYNOPSIS

   use AnyEvent;
   use Tk;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Tk work with AnyEvent except by loading Tk before
creating the first AnyEvent watcher.

Tk is buggy. Tk is extremely buggy. Tk is so unbelievably buggy that
for each bug reported and fixed, you get one new bug followed by
reintroduction of the old bug in a later revision. It is also basically
unmaintained: the maintainers are not even interested in improving
the situation - reporting bugs is considered rude, and fixing bugs is
considered changing holy code, so it's apparently better to leave it
broken.

I regularly run out of words to describe how bad it really is.

To work around some of the many, many bugs in Tk that don't get fixed,
this adaptor dup()'s all filehandles that get passed into its I/O
watchers, so if you register a read and a write watcher for one fh,
AnyEvent will create two additional file descriptors (and handles).

This creates a high overhead and is slow, but seems to work around most
known bugs in L<Tk::fileevent> on 32 bit architectures (Tk seems to be
terminally broken on 64 bit, do not expect more than 10 or so watchers to
work on 64 bit machines).

Do not expect these workarounds to avoid segfaults and crashes inside Tk.

Note also that Tk event ids wrap around after 2**32 or so events, which on
my machine can happen within less than 12 hours, after which Tk will stomp
on random other events and kill them. So don't run Tk programs for more
than an hour or so.

To be able to access the Tk event loop, this module creates a main
window and withdraws it immediately. This might cause flickering on some
platforms, but Tk perversely requires a window to be able to wait for file
handle readyness notifications. This window is always created (in this
version of AnyEvent) and can be accessed as C<$AnyEvent::Impl::Tk::mw>.

=cut

package AnyEvent::Impl::Tk;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Tk ();

our $mw = new MainWindow -title => "AnyEvent Dummy Window";
$mw->withdraw;

END { undef $mw }

sub io {
   my (undef, %arg) = @_;

   # work around these bugs in Tk:
   # - removing a callback will destroy other callbacks
   # - removing a callback might crash
   # - adding a callback might destroy other callbacks
   # - only one callback per fh
   # - only one callback per fh/poll combination
   my ($fh, $tk) = AnyEvent::_dupfh $arg{poll}, $arg{fh}, "readable", "writable";

   $mw->fileevent ($fh, $tk => $arg{cb});

   bless [$fh, $tk], "AnyEvent::Impl::Tk::io"
}

sub AnyEvent::Impl::Tk::io::DESTROY {
   my ($fh, $tk) = @{$_[0]};

   # work around another bug: watchers don't get removed when
   # the fh is closed, contrary to documentation. also, trying
   # to unregister a read callback will make it impossible
   # to remove the write callback.
   # if your program segfaults here then you need to destroy
   # your watchers before program exit. sorry, no way around
   # that.
   $mw->fileevent ($fh, $tk => "");
}

sub timer {
   my (undef, %arg) = @_;
   
   my $after = $arg{after} < 0 ? 0 : $arg{after} * 1000;
   my $cb = $arg{cb};
   my $id;

   if ($arg{interval}) {
      my $ival = $arg{interval} * 1000;
      my $rcb = sub {
         $id = Tk::after $mw, $ival, [$_[0], $_[0]];
         &$cb;
      };
      $id = Tk::after $mw, $after, [$rcb, $rcb];
   } else {
      # tk blesses $cb, thus the extra indirection
      $id = Tk::after $mw, $after, sub { &$cb };
   }

   bless \\$id, "AnyEvent::Impl::Tk::after"
}

sub idle {
   my (undef, %arg) = @_;

   my $cb = $arg{cb};
   my $id;
   my $rcb = sub {
      # in their endless stupidity, they decided to give repeating idle watchers
      # strictly higher priority than timers :/
      $id = Tk::after $mw, 0 => [sub {
         $id = Tk::after $mw, idle => [$_[0], $_[0]];
      }, $_[0]];
      &$cb;
   };

   $id = Tk::after $mw, idle => [$rcb, $rcb];
   bless \\$id, "AnyEvent::Impl::Tk::after"
}

sub AnyEvent::Impl::Tk::after::DESTROY {
   Tk::after $mw, cancel => $${$_[0]};
}

#sub loop {
#   Tk::MainLoop;
#}

sub _poll {
   Tk::DoOneEvent (0);
}

sub AnyEvent::CondVar::Base::_wait {
   Tk::DoOneEvent (0) until exists $_[0]{_ae_sent};
}

=head1 SEE ALSO

L<AnyEvent>, L<Tk>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

