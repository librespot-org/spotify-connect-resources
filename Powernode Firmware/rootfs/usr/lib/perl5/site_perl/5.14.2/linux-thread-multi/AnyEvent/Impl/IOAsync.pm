=head1 NAME

AnyEvent::Impl::IOAsync - AnyEvent adaptor for IO::Async

=head1 SYNOPSIS

  use AnyEvent;
  use IO::Async::Loop;

  # optionally set another event loop
  use AnyEvent::Impl::IOAsync;
  my $loop = new IO::Async::Loop;
  AnyEvent::Impl::IOAsync::set_loop $loop;

=head1 DESCRIPTION

This module provides support for IO::Async as AnyEvent backend. It supports
I/O, timers, signals and child process watchers. Idle watchers are emulated.
I/O watchers need to dup their fh because IO::Async only supports IO handles,
not plain file descriptors.

=head1 PROBLEMS WITH IO::Async

This section had a long list of problems and shortcomings that made it
almost impossible to support L<IO::Async>. With version 0.33 of IO::Async,
however, most of these have been fixed, so L<IO::Async> can now be used as
easily as many other loops.

There are a few remaining problems that require emulation or workarounds:

=over 4

=item No support for multiple watchers per event

In most (all? documentation?) cases you cannot have multiple watchers
for the same event (what's the point of having all these fancy notifier
classes when you cannot have multiple notifiers for the same event? That's
like only allowing one timer per second or so...).

For I/O watchers, AnyEvent has to dup() every file handle, as IO::Async
fails to support the same or different file handles pointing to the same
fd (the good thing is that it is documented, but why not fix it instead?).

=back

Apart from these fatal flaws, there are a number of unpleasent properties
that just need some mentioning:

=over 4

=item Confusing and misleading names

Another rather negative point about this module family is its name,
which is deeply confusing: Despite the "async" in the name, L<IO::Async>
only does I<synchronous> I/O, there is nothing "asynchronous" about it
whatsoever (when I first heard about it, I thought, "wow, a second async
I/O module, what does it do compared to L<IO::AIO>", and was somehow set
back when I learned that the only "async" aspect of it is the name).

=item Inconsistent, incomplete and convoluted API

Implementing AnyEvent's rather simple timers on top of IO::Async's timers
was a nightmare (try implementing a timer with configurable interval and
delay value...).

The method naming is chaotic: C<watch_child> creates a child watcher,
but C<watch_io> is an internal method; C<detach_signal> removes a signal
watcher, but C<detach_child> forks a subprocess and so on).

=item Unpleasant surprises on GNU/Linux

When you develop your program on FreeBSD and run it on GNU/Linux, you
might have unpleasant surprises, as IO::Async::Loop will by default use
L<IO::Async::Loop::Epoll>, which is incompatible with C<fork>, so your
network server will run into spurious and very hard to debug problems
under heavy load, as IO::Async forks a lot of processes, e.g. for DNS
resolution. It would be better if IO::Async would only load "safe"
backends by default (or fix the epoll backend to work in the presence of
fork, which admittedly is hard - EV does it for you, and also does not use
unsafe backends by default).

=back

On the positive side, performance with IO::Async is quite good even in my
very demanding eyes.

=cut

package AnyEvent::Impl::IOAsync;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use Time::HiRes ();
use Scalar::Util ();

use IO::Async::Loop 0.33;

our $LOOP = new IO::Async::Loop;

sub set_loop($) {
   $LOOP = $_[0];
}

sub timer {
   my ($class, %arg) = @_;
   
   my $cb = $arg{cb};

   my $id;

   if (my $ival = $arg{interval}) {
      my $ival_cb; $ival_cb = sub {
         $id = $LOOP->enqueue_timer (delay => $ival, code => $ival_cb);
         &$cb;
      };
      $id = $LOOP->enqueue_timer (delay => $arg{after}, code => $ival_cb);

      # we have to weaken afterwards, but when enqueue dies, we have a memleak.
      # still, we do anything for speed...
      Scalar::Util::weaken $ival_cb;

   } else {
      # IO::Async has problems with overloaded objects
      $id = $LOOP->enqueue_timer (delay => $arg{after}, code => sub {
         undef $id; # IO::Async <= 0.43 bug workaround
         &$cb;
      });
   }

   bless \\$id, "AnyEvent::Impl::IOAsync::timer"
}

sub AnyEvent::Impl::IOAsync::timer::DESTROY {
   # Need to be well-behaved during global destruction
   $LOOP->cancel_timer (${${$_[0]}})
      if defined ${${$_[0]}}; # IO::Async <= 0.43 bug workaround
}

sub io {
   my ($class, %arg) = @_;

   # Ensure we have a real IO handle, and not just a UNIX fd integer
   my ($fh) = AnyEvent::_dupfh $arg{poll}, $arg{fh};

   my $event = $arg{poll} eq "r" ? "on_read_ready" : "on_write_ready";

   $LOOP->watch_io (
      handle => $fh,
      $event => $arg{cb},
   );

   bless [$fh, $event], "AnyEvent::Impl::IOAsync::io"
}

sub AnyEvent::Impl::IOAsync::io::DESTROY {
   $LOOP->unwatch_io (
      handle => $_[0][0],
      $_[0][1] => 1,
   );
}

sub signal {
   my ($class, %arg) = @_;

   my $signal = $arg{signal};

   my $id = $LOOP->attach_signal ($arg{signal}, $arg{cb});
   bless [$signal, $id], "AnyEvent::Impl::IOAsync::signal"
}

sub AnyEvent::Impl::IOAsync::signal::DESTROY {
   $LOOP->detach_signal (@{ $_[0] });
}

our %pid_cb;

sub child {
   my ($class, %arg) = @_;

   my $pid = $arg{pid};

   $LOOP->watch_child ($pid, $arg{cb});
   bless [$pid], "AnyEvent::Impl::IOAsync::child"
}

sub child {
   my ($class, %arg) = @_;

   my $pid = $arg{pid};
   my $cb  = $arg{cb};

   unless (%{ $pid_cb{$pid} }) {
      $LOOP->watch_child ($pid, sub {
         $_->($_[0], $_[1])
            for values %{ $pid_cb{$pid} };
      });
   }

   $pid_cb{$pid}{$cb+0} = $cb;

   bless [$pid, $cb+0], "AnyEvent::Impl::IOAsync::child"
}

sub AnyEvent::Impl::IOAsync::child::DESTROY {
   my ($pid, $icb) = @{ $_[0] };

   delete $pid_cb{$pid}{$icb};

   unless (%{ $pid_cb{$pid} }) {
      delete $pid_cb{$pid};
      $LOOP->unwatch_child ($pid);
   }
}

#sub loop {
#   $LOOP->loop_forever;
#}

sub _poll {
   $LOOP->loop_once;
}

sub AnyEvent::CondVar::Base::_wait {
   $LOOP->loop_once until exists $_[0]{_ae_sent};
}

=head1 SEE ALSO

L<AnyEvent>, L<IO::Async>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

 Paul Evans <leonerd@leonerd.org.uk>
 Rewrote the backend for IO::Async version 0.33.

=cut

1

