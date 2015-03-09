=head1 NAME

AnyEvent::Impl::Cocoa - AnyEvent adaptor for Cocoa::EventLoop

=head1 SYNOPSIS

    use AnyEvent;
    use Cocoa::EventLoop;
    
    # do something

=head1 DESCRIPTION

This module provides NSRunLoop support to AnyEvent.

NSRunLoop is an event loop for Cocoa applications, wrapped by
L<Cocoa::EventLoop>. By using this module, you can use Cocoa based API in
your AnyEvent application, or AnyEvent within Cocoa applications.

It does not support blocking waits.

=head1 BUGS

Right now, L<Cocoa::EventLoop> (and this module) are in an early
development phase and has some shortcomings and likely bugs.

For example, there seems to be no way to just handle a single event
with Cocoa (is there nothing they can implement properly?), so this
module currently wakes up at least ten times a second when waiting for
events. Also, events caused by timers might get delayed by up to 0.1
seconds.

=cut

package AnyEvent::Impl::Cocoa;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use Cocoa::EventLoop;

sub io {
   my ($class, %arg) = @_;

   Cocoa::EventLoop->io (%arg)
}

sub timer {
   my ($class, %arg) = @_;

   Cocoa::EventLoop->timer (%arg)
}

# does not support blocking waits

#sub loop {
#   Cocoa::EventLoop->run;
#}

=head1 AUTHORS

Daisuke Murase <typester@cpan.org>, Marc Lehmann <schmorp@schmorp.de>.

=head1 COPYRIGHTS

   Copyright (c) 2009 by KAYAC Inc.
   Copyright (c) 2010,2011 by Marc Lehmann <schmorp@schmorp.de>

=cut

1

