=head1 NAME

AnyEvent::Impl::Event - AnyEvent adaptor for Event

=head1 SYNOPSIS

   use AnyEvent;
   use Event;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Event work with AnyEvent except by loading Event before
creating the first AnyEvent watcher.

The event module is reasonably efficient and generally works correctly
even with many watchers, except that its signal handling is inherently
racy and requires the wake-up-frequently workaround.

=cut

package AnyEvent::Impl::Event;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Event qw(unloop); # we have to import something to make Event use Time::HiRes

sub io {
   my (undef, %arg) = @_;
   $arg{fd} = delete $arg{fh};
   $arg{poll} .= "e" if AnyEvent::WIN32; # work around windows connect bug
   my $cb = $arg{cb}; $arg{cb} = sub { &$cb }; # event doesn't like callable objects
   bless \(Event->io (%arg)), __PACKAGE__
}

sub timer {
   my (undef, %arg) = @_;
   $arg{after} = 0 if $arg{after} < 0;
   my $cb = $arg{cb}; $arg{cb} = sub { &$cb }; # event doesn't like callable objects
   bless \Event->timer (%arg, repeat => $arg{interval}), __PACKAGE__
}

sub idle {
   my (undef, %arg) = @_;
   my $cb = $arg{cb}; $arg{cb} = sub { &$cb }; # event doesn't like callable objects
   bless \Event->idle (repeat => 1, min => 0, %arg), __PACKAGE__
}

sub DESTROY {
   ${$_[0]}->cancel;
}

sub signal {
   my (undef, %arg) = @_;

   my $cb = $arg{cb};
   my $w = Event->signal (
      signal => AnyEvent::Base::sig2name $arg{signal},
      cb     => sub { &$cb }, # event doesn't like callable objects
   );

   AnyEvent::Base::_sig_add;
   bless \$w, "AnyEvent::Impl::Event::signal"
}

sub AnyEvent::Impl::Event::signal::DESTROY {
   AnyEvent::Base::_sig_del;
   ${$_[0]}->cancel;
}

sub _poll {
   Event::one_event;
}

sub AnyEvent::CondVar::Base::_wait {
   Event::one_event until exists $_[0]{_ae_sent};
}

#sub loop {
#   Event::loop;
#}

=head1 SEE ALSO

L<AnyEvent>, L<Event>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

