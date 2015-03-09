=head1 NAME

AnyEvent::Impl::Qt - AnyEvent adaptor for Qt

=head1 SYNOPSIS

   use AnyEvent;
   use Qt;
  
   my $app = Qt::Application \@ARGV; # REQUIRED!
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have
to do anything to make Qt work with AnyEvent except by loading Qt
before creating the first AnyEvent watcher I<and instantiating the
Qt::Application object>. Failure to do so will result in segfaults,
which is why this model doesn't work as a default model and will not be
autoprobed (but it will be autodetected when the main program uses Qt).

Qt suffers from the same limitations as Event::Lib and Tk, the workaround
is also the same (duplicating file descriptors).

Qt doesn't support idle events, so they are being emulated.

Avoid Qt if you can.

=cut

package AnyEvent::Impl::Qt::Io;

use Qt;
use Qt::isa qw(Qt::SocketNotifier); # Socket? what where they smoking
use Qt::slots cb => [];

sub NEW {
   my ($class, $fh, $mode, $cb) = @_;
   shift->SUPER::NEW (fileno $fh, $mode);
   this->{fh} = $fh;
   this->{cb} = $cb;
   this->connect (this, SIGNAL "activated(int)", SLOT "cb()");
}

sub cb {
   this->setEnabled (0); # required according to the docs. heavy smoking required.
   this->{cb}->();
   this->setEnabled (1);
}

package AnyEvent::Impl::Qt::Timer;

use Qt;
use Qt::isa qw(Qt::Timer);
use Qt::slots cb => [];

# having to go through these contortions just to get a timer event is
# considered an advantage over other gui toolkits how?

sub NEW {
   my ($class, $after, $interval, $cb) = @_;
   shift->SUPER::NEW ();
   this->{interval} = $interval;
   this->{cb}       = $cb;
   this->connect (this, SIGNAL "timeout()", SLOT "cb()");
   this->start ($after, 1);
}

sub cb {
   this->start (this->{interval}, 1) if defined this->{interval};
   this->{cb}->();
}

package AnyEvent::Impl::Qt;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Qt;

use AnyEvent::Impl::Qt::Timer;
use AnyEvent::Impl::Qt::Io;

our $app = Qt::Application \@ARGV; # REQUIRED!

sub io {
   my ($class, %arg) = @_;

   # work around these bugs in Qt:
   # - adding a callback might destroy other callbacks
   # - only one callback per fd/poll combination
   my ($fh, $qt) = AnyEvent::_dupfh $arg{poll}, $arg{fh},
                      Qt::SocketNotifier::Read (), Qt::SocketNotifier::Write ();

   AnyEvent::Impl::Qt::Io $fh, $qt, $arg{cb}
}

sub timer {
   my ($class, %arg) = @_;
   
   # old Qt treats 0 timeout as "idle"
   AnyEvent::Impl::Qt::Timer
      $arg{after} * 1000 || 1,
      $arg{interval} ? $arg{interval} * 1000 || 1 : undef,
      $arg{cb}
}

# newer Qt have no idle mode for timers anymore...
#sub idle {
#   my ($class, %arg) = @_;
#   
#   AnyEvent::Impl::Qt::Timer 0, 0, $arg{cb}
#}

#sub loop {
#   Qt::app->exec;
#}

sub _poll {
   Qt::app->processOneEvent;
}

sub AnyEvent::CondVar::Base::_wait {
   Qt::app->processOneEvent until exists $_[0]{_ae_sent};
}

=head1 SEE ALSO

L<AnyEvent>, L<Qt>.

=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://anyevent.schmorp.de

=cut

1

