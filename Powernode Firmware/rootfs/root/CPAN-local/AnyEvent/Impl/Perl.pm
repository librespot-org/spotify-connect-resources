=head1 NAME

AnyEvent::Impl::Perl - AnyEvent adaptor for AnyEvent's pure perl AnyEvent::Loop

=head1 SYNOPSIS

   use AnyEvent;
   use AnyEvent::Loop;
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent in case no other
event loop could be found or loaded.

If you want to use this module instead of autoloading another event loop
you can simply load L<AnyEvent::Loop> before creating the first watcher.

Naturally, it supports all features of AnyEvent.

See L<AnyEvent::Loop> for more details on performance characteristics.

=cut

package AnyEvent::Impl::Perl;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Loop;

our $VERSION = $AnyEvent::VERSION;

# time() is provided via AnyEvent::Base

*AE::now        = \&AnyEvent::Loop::now;
*AE::now_update = \&AnyEvent::Loop::now_update;
*AE::io         = \&AnyEvent::Loop::io;
*AE::timer      = \&AnyEvent::Loop::timer;
*AE::idle       = \&AnyEvent::Loop::idle;
*_poll          = \&AnyEvent::Loop::one_event;
*loop           = \&AnyEvent::Loop::run; # compatibility with AnyEvent < 6.0

sub now        { $AnyEvent::Loop::NOW }
sub now_update { AE::now_update       }

sub AnyEvent::CondVar::Base::_wait {
   AnyEvent::Loop::one_event until exists $_[0]{_ae_sent};
}

sub io {
   my (undef, %arg) = @_;

   AnyEvent::Loop::io $arg{fh}, $arg{poll} eq "w", $arg{cb}
}

sub timer {
   my (undef, %arg) = @_;

   AnyEvent::Loop::timer $arg{after}, $arg{interval}, $arg{cb}
}

sub idle {
   my (undef, %arg) = @_;

   AnyEvent::Loop::idle $arg{cb}
}

=head1 SEE ALSO

L<AnyEvent>.

=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://anyevent.schmorp.de

=cut

1

