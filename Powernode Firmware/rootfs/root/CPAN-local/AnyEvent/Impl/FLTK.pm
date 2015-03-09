=head1 NAME

AnyEvent::Impl::FLTK - AnyEvent adaptor for FLTK (Fast Light Toolkit version two)

=head1 SYNOPSIS

   use AnyEvent;
   use FLTK;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make FLTK work with AnyEvent except by loading FLTK before
creating the first AnyEvent watcher.

This implementation is not to be confused with AnyEvent::Impl::FLTK by
Sanko Robinson. That implementation is completely broken, and the author
is apparently unreachable.

In any case, FLTK suffers from typical GUI-ToolKit diseases, such as O(n)
or worse for every operation (adding a timer, destroying a timer etc.),
the typical Not-Well-Tested Perl Interface disases such as non-random
memory corruption and the typical Event-Loop-as-an-Afterthrough issues,
such as multiple watchers on the same fd silently overwriting the others.

It doesn't have native idle, signal or child watchers, so all of these are
emulated.

=cut

package AnyEvent::Impl::FLTK;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use FLTK 0.532 ();
use Scalar::Util ();

#*AE::timer      = \&EV::timer;
#*AE::signal     = \&EV::signal;
#*AE::idle       = \&EV::idle;

# FLTK::get_time_secs returns a glob :/
# on unix, fltk uses gettimeofday, so we are likely compatible
# on windows, fltk uses GetTickCount, to which we are unlikely to be compatible with.
#sub time { FLTK::get_time_secs }
#*now = \&time;

sub timer_interval_cb {
   my $id = shift; # add_timeout kills @_, so we have to make a copy :(
   $id->[0] = FLTK::add_timeout $id->[1], \&timer_interval_cb, $id;
   &{ $id->[2] }
}

sub timer {
   my ($class, %arg) = @_;

   my $cb = $arg{cb};

   if ($arg{interval}) {
      my $id = [undef, $arg{interval}, $cb];

      $id->[0] = FLTK::add_timeout $arg{after}, \&timer_interval_cb, $id;

      return bless $id, "AnyEvent::Impl::FLTK::timer"
   } else {
      # non-repeating timers can be done very efficiently
      # also, FLTK doesn't like callable objects
      return FLTK::add_timeout $arg{after}, sub { &$cb }
   }
}

sub AnyEvent::Impl::FLTK::timer::DESTROY {
   undef $_[0][0];
}

sub io {
   my ($class, %arg) = @_;

   # only one watcher/fd :(

   my $cb = $arg{cb};
   my ($fh, $ev) = AnyEvent::_dupfh $arg{poll}, $arg{fh},
      FLTK::READ,
      FLTK::WRITE | (AnyEvent::WIN32 ? FLTK::EXCEPT : 0);

   # fltk hardcodes poll constants and aliases EXCEPT with POLLERR,
   # which is grossly wrong, but likely it doesn't use poll on windows.
   FLTK::add_fd $fh, $ev, sub { &$cb }
}

# use signal and child emulation - fltk has no facilities for that

# fltk idle watchers are like EV::check watchers, and fltk check watchers
# are like EV::prepare watchers. both are called when the loop is busy,
# so we have to use idle watcher emulation.

sub _poll {
   FLTK::wait;
}

sub AnyEvent::CondVar::Base::_wait {
   FLTK::wait until exists $_[0]{_ae_sent};
}

#sub loop {
#   FLTK::run;
#}

=head1 SEE ALSO

L<AnyEvent>, L<FLTK>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

