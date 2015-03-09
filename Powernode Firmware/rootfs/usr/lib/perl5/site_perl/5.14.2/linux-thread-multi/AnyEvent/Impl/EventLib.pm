=head1 NAME

AnyEvent::Impl::EventLib - AnyEvent adaptor for Event::Lib

=head1 SYNOPSIS

   use AnyEvent;
   use Event::Lib;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Event work with AnyEvent except by loading Event::Lib
before creating the first AnyEvent watcher.

Note: the AnyEvent author has not found recent releases of Event::Lib to
be even remotely working (not even the examples from the manpage or the
testsuite work), so this event backend should be avoided (or somebody
should step up and maintain it, hint, hint).

The L<Event::Lib> module suffers from the same limitations and bugs as
libevent, most notably it kills already-installed watchers on a file
descriptor and it is unable to support fork. These are not fatal issues,
and are worked-around by this module, but the L<Event::Lib> perl module
itself has many additional bugs such as taking references to file handles
and callbacks instead of making a copy or freeing still-allocated scalars,
causing memory corruption and random crashes. Only Tk rivals it in its
brokenness.

This adaptor module employs the same workaround around the watcher
problems as Tk and should therefore be avoided. (This was done for
simplicity, one could in theory work around the problems with lower
overhead by managing our own watchers).

Event::Lib also leaks file handles and memory and tends to just exit on
problems.

It also doesn't work around the Windows bug of not signalling TCP
connection failures.

It also doesn't work with many special devices on Linux (F</dev/random>
works, F</dev/urandom> fails, F</dev/tty> works, F</dev/null> fails and so
on).

Event::Lib does not support idle watchers. They could be emulated using
low-priority timers but as the priority range (and availability) is not
queryable nor guaranteed, and the default priority is likely the lowest
one, this module cannot use them.

Avoid Event::Lib if you can.

=cut

package AnyEvent::Impl::EventLib;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use Event::Lib;

# Event::Lib doesn't always take a reference to the callback, so closures
# cause memory corruption and segfaults. it also has an issue actually
# calling callbacks, so this exists as workaround.
sub ccb {
   # Event:Lib accesses $_[0] after the callback, when it might be freed,
   # so we keep it referenced until after the callback. This still accesses
   # a freed scalar, but at least it'll not crash.
   my $keep_it = $_[0];

   $_[2]();
}

my $ccb = \&ccb;

sub io {
   my (undef, %arg) = @_;

   # work around these bugs in Event::Lib:
   # - adding a callback might destroy other callbacks
   # - only one callback per fd/poll combination
   my ($fh, $mode) = AnyEvent::_dupfh $arg{poll}, $arg{fh}, EV_READ, EV_WRITE;

   # event_new errornously takes a reference to fh and cb instead of making a copy
   # fortunately, going through %arg/_dupfh already makes a copy, so it happpens to work
   my $w = event_new $fh, $mode | EV_PERSIST, $ccb, $arg{cb};
   event_add $w;
   bless \\$w, __PACKAGE__
}

sub timer {
   my (undef, %arg) = @_;

   my $ival = $arg{interval};
   my $cb   = $arg{cb};

   my $w; $w = timer_new $ccb,
                  $ival
                     ? sub { event_add $w, $ival; &$cb }
                     : sub { undef $w           ; &$cb };

   event_add $w, $arg{after} || 1e-10; # work around 0-bug in Event::Lib

   bless \\$w, __PACKAGE__
}

sub DESTROY {
   local $@;
   ${${$_[0]}}->remove;
}

sub signal {
   my (undef, %arg) = @_;

   my $w = signal_new AnyEvent::Base::sig2num $arg{signal}, $ccb, $arg{cb};
   event_add $w;
   AnyEvent::Base::_sig_add;
   bless \\$w, "AnyEvent::Impl::EventLib::signal"
}

sub AnyEvent::Impl::EventLib::signal::DESTROY {
   AnyEvent::Base::_sig_del;
   local $@;
   ${${$_[0]}}->remove;
}

#sub loop {
#   event_mainloop;
#}

sub _poll {
   event_one_loop;
}

sub AnyEvent::CondVar::Base::_wait {
   event_one_loop until exists $_[0]{_ae_sent};
}

=head1 SEE ALSO

L<AnyEvent>, L<Event::Lib>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

