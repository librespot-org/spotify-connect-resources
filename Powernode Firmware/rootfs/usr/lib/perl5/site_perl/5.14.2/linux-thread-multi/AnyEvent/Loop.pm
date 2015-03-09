=head1 NAME

AnyEvent::Loop - AnyEvent's Pure-Perl event loop

=head1 SYNOPSIS

   use AnyEvent;
   # use AnyEvent::Loop;
  
   # this module gets loaded automatically when no other loop can be found

   # Explicit use:
   use AnyEvent::Loop;
   use AnyEvent;

   ...

   AnyEvent::Loop::run; # run the event loop

=head1 DESCRIPTION

This module provides an event loop for AnyEvent in case no other event
loop could be found or loaded. You don't have to do anything to make it
work with AnyEvent except by possibly loading it before creating the first
AnyEvent watcher.

This module is I<not> some loop abstracion used by AnyEvent, but just
another event loop like EV or Glib, just written in pure perl and
delivered with AnyEvent, so AnyEvent always works, even in the absence of
any other backend.

If you want to use this module instead of autoloading a potentially better
event loop you can simply load it (and no other event loops) before
creating the first watcher.

As for performance, this module is on par with (and usually faster than)
most select/poll-based C event modules such as Event or Glib (it does not
even come close to EV, though), with respect to I/O watchers. Timers are
handled less optimally, but for many common tasks, it is still on par with
event loops written in C.

This event loop has been optimised for the following use cases:

=over 4

=item monotonic clock is available

This module will use the POSIX monotonic clock option (if it can be
detected at runtime) or the POSIX C<times> function (if the resolution
is at least 100Hz), in which case it will not suffer adversely from time
jumps.

If no monotonic clock is available, this module will not attempt to
correct for time jumps in any way.

The clock chosen will be reported if the environment variable
C<$PERL_ANYEVENT_VERBOSE> is set to 8 or higher.

=item any number of watchers on one fd

Supporting a large number of watchers per fd is purely a dirty benchmark
optimisation not relevant in practise. The more common case of having one
watcher per fd/poll combo is special-cased, however, and therefore fast,
too.

=item relatively few active fds per C<select> call

This module expects that only a tiny amount of fds is active at any one
time. This is relatively typical of larger servers (but not the case where
C<select> traditionally is fast), at the expense of the "dense activity
case" where most of the fds are active (which suits C<select>).

The optimal implementation of the "dense" case is not much faster, though,
so the module should behave very well in most cases, subject to the bad
scalability of C<select> in the presence of a large number of inactive
file descriptors.

=item lots of timer changes/iteration, or none at all

This module sorts the timer list using perl's C<sort>, even though a total
ordering is not required for timers internally.

This sorting is expensive, but means sorting can be avoided unless the
timer list has changed in a way that requires a new sort.

This means that adding lots of timers is very efficient, as well as not
changing the timers. Advancing timers (e.g. recreating a timeout watcher
on activity) is also relatively efficient, for example, if you have a
large number of timeout watchers that time out after 10 seconds, then the
timer list will be sorted only once every 10 seconds.

This should not have much of an impact unless you have hundreds or
thousands of timers, though, or your timers have very small timeouts.

=back

=head1 FUNCTIONS

The only user-visible functions provided by this module loop related -
watchers are created via the normal AnyEvent mechanisms.

=over 4

=item AnyEvent::Loop::run

Run the event loop, usually the last thing done in the main program when
you want to use the pure-perl backend.

=item AnyEvent::Loop::one_event

Blocks until at least one new event has been received by the operating
system, whether or not it was AnyEvent-related.

=back

=cut

package AnyEvent::Loop;

use Scalar::Util qw(weaken);
use List::Util ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();

our $VERSION = $AnyEvent::VERSION;

our ($NOW, $MNOW);

sub MAXWAIT() { 3600 } # never sleep for longer than this many seconds

BEGIN {
   local $SIG{__DIE__};
   my $time_hires = eval "use Time::HiRes (); 1";
   my $clk_tck    = eval "use POSIX (); POSIX::sysconf (POSIX::_SC_CLK_TCK ())";
   my $round; # actual granularity

   if ($time_hires && eval "&Time::HiRes::clock_gettime (Time::HiRes::CLOCK_MONOTONIC ())") {
      AE::log 8 => "Using CLOCK_MONOTONIC as timebase.";
      *_update_clock = sub {
         $NOW  = &Time::HiRes::time;
         $MNOW = Time::HiRes::clock_gettime (&Time::HiRes::CLOCK_MONOTONIC);
      };

   } elsif (100 <= $clk_tck && $clk_tck <= 1000000 && eval { (POSIX::times ())[0] != -1 }) { # -1 is also a valid return value :/
      AE::log 8 => "Using POSIX::times (monotonic) as timebase.";
      my $HZ1 = 1 / $clk_tck;

      my $last = (POSIX::times ())[0];
      my $next;
      *_update_clock = sub {
         $NOW  = time; # d'oh

         $next = (POSIX::times ())[0];
         # we assume 32 bit signed on wrap but 64 bit will never wrap
         $last -= 4294967296 if $last > $next; # 0x100000000, but perl has probelsm with big hex constants
         $MNOW += ($next - $last) * $HZ1;
         $last = $next;
      };

      $round = $HZ1;

   } elsif (eval "use Time::HiRes (); 1") {
      AE::log 8 => "Using Time::HiRes::time (non-monotonic) clock as timebase.";
      *_update_clock = sub {
         $NOW = $MNOW = &Time::HiRes::time;
      };

   } else {
      AE::log fatal => "Unable to find sub-second time source (is this really perl 5.8.0 or later?)";
   }

   $round = 0.001 if $round < 0.001; # 1ms is enough for us
   $round -= $round * 1e-2; # 0.1 => 0.099
   eval "sub ROUNDUP() { $round }";
}

_update_clock;

# rely on AnyEvent:Base::time to provide time
sub now       () { $NOW          }
sub now_update() { _update_clock }

# fds[0] is for read, fds[1] is for write watchers
# fds[poll][V] is the bitmask for select
# fds[poll][W][fd] contains a list of i/o watchers
# an I/O watcher is a blessed arrayref containing [fh, poll(0/1), callback, queue-index]
# the queue-index is simply the index in the [W] array, which is only used to improve
# benchmark results in the synthetic "many watchers on one fd" benchmark.
my @fds = ([], []);
sub V() { 0 }
sub W() { 1 }

my $need_sort = 1e300; # when to re-sort timer list
my @timer; # list of [ abs-timeout, Timer::[callback] ]
my @idle;  # list of idle callbacks

# the pure perl mainloop
sub one_event {
   _update_clock;

   # first sort timers if required (slow)
   if ($MNOW >= $need_sort) {
      $need_sort = 1e300;
      @timer = sort { $a->[0] <=> $b->[0] } @timer;
   }

   # handle all pending timers
   if (@timer && $timer[0][0] <= $MNOW) {
      do {
         my $timer = shift @timer;
         $timer->[1] && $timer->[1]($timer);
      } while @timer && $timer[0][0] <= $MNOW;

   } else {
      # poll for I/O events, we do not do this when there
      # were any pending timers to ensure that one_event returns
      # quickly when some timers have been handled
      my ($wait, @vec, $fds)
         = (@timer && $timer[0][0] < $need_sort ? $timer[0][0] : $need_sort) - $MNOW;

      $wait = $wait < MAXWAIT ? $wait + ROUNDUP : MAXWAIT;
      $wait = 0 if @idle;

      $fds = CORE::select
        $vec[0] = $fds[0][V],
        $vec[1] = $fds[1][V],
        AnyEvent::WIN32 ? $vec[2] = $fds[1][V] : undef,
        $wait;

      _update_clock;

      if ($fds > 0) {
         # buggy microshit windows errornously sets exceptfds instead of writefds
         $vec[1] |= $vec[2] if AnyEvent::WIN32;

         # prefer write watchers, because they might reduce memory pressure.
         for (1, 0) {
            my $fds = $fds[$_];

            # we parse the bitmask by first expanding it into
            # a string of bits
            for (unpack "b*", $vec[$_]) {
               # and then repeatedly matching a regex against it
               while (/1/g) {
                  # and use the resulting string position as fd
                  $_ && $_->[2]()
                     for @{ $fds->[W][(pos) - 1] || [] };
               }
            }
         }
      } elsif (AnyEvent::WIN32 && $fds && $! == AnyEvent::Util::WSAEINVAL) {
         # buggy microshit windoze asks us to route around it
         CORE::select undef, undef, undef, $wait if $wait;
      } elsif (!@timer || $timer[0][0] > $MNOW && !$fds) {
         $$$_ && $$$_->() for @idle = grep $$$_, @idle;
      }
   }
}

sub run {
   one_event while 1;
}

sub io($$$) {
   my ($fd, $write, $cb) = @_;

   defined ($fd = fileno $fd)
      or $fd = $_[0];

   my $self = bless [
      $fd,
      $write,
      $cb,
      # q-idx
   ], "AnyEvent::Loop::io";

   my $fds = $fds[$self->[1]];

   # add watcher to fds structure
   my $q = $fds->[W][$fd] ||= [];

   (vec $fds->[V], $fd, 1) = 1;

   $self->[3] = @$q;
   push @$q, $self;
   weaken $q->[-1];

   $self
}

sub AnyEvent::Loop::io::DESTROY {
   my ($self) = @_;

   my $fds = $fds[$self->[1]];

   # remove watcher from fds structure
   my $fd = $self->[0];

   if (@{ $fds->[W][$fd] } == 1) {
      delete $fds->[W][$fd];
      (vec $fds->[V], $fd, 1) = 0;
   } else {
      my $q = $fds->[W][$fd];
      my $last = pop @$q;

      if ($last != $self) {
         weaken ($q->[$self->[3]] = $last);
         $last->[3] = $self->[3];
      }
   }
}

sub timer($$$) {
   my ($after, $interval, $cb) = @_;
   
   my $self;

   if ($interval) {
      $self = [$MNOW + $after , sub {
         $_[0][0] = List::Util::max $_[0][0] + $interval, $MNOW;
         push @timer, $_[0];
         weaken $timer[-1];
         $need_sort = $_[0][0] if $_[0][0] < $need_sort;
         &$cb;
      }];
   } else {
      $self = [$MNOW + $after, $cb];
   }

   push @timer, $self;
   weaken $timer[-1];
   $need_sort = $self->[0] if $self->[0] < $need_sort;

   $self
}

sub idle($) {
   my $cb = shift;

   push @idle, \\$cb;
   weaken ${$idle[-1]};

   ${$idle[-1]}
}

=head1 SEE ALSO

L<AnyEvent>.

=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://anyevent.schmorp.de

=cut

1

