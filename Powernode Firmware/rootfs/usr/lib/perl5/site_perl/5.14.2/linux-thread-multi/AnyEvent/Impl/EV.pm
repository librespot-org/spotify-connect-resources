=head1 NAME

AnyEvent::Impl::EV - AnyEvent adaptor for EV

=head1 SYNOPSIS

   use AnyEvent;
   use EV;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make EV work with AnyEvent except by loading EV before
creating the first AnyEvent watcher.

EV is the fastest event library for perl, and best supported by
AnyEvent. Most functions from the L<AE> API are implemented as direct
aliases to EV functions, so using EV via AE is as fast as using EV
directly.

=cut

package AnyEvent::Impl::EV;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use EV 4.00;

*AE::time       = \&EV::time;
*AE::now        = \&EV::now;
*AE::now_update = \&EV::now_update;
*AE::timer      = \&EV::timer;
*AE::signal     = \&EV::signal;
*AE::idle       = \&EV::idle;

# cannot override directly, as EV doesn't allow arguments
sub time       { EV::time       }
sub now        { EV::now        }
sub now_update { EV::now_update }

*AE::io = defined &EV::_ae_io # 3.8+, but keep just in case it is dropped
   ? \&EV::_ae_io
   : sub($$$) { EV::io $_[0], $_[1] ? EV::WRITE : EV::READ, $_[2] };

sub timer {
   my ($class, %arg) = @_;

   EV::timer $arg{after}, $arg{interval}, $arg{cb}
}

sub io {
   my ($class, %arg) = @_;

   EV::io
      $arg{fh},
      $arg{poll} eq "r" ? EV::READ : EV::WRITE,
      $arg{cb}
}

sub signal {
   my ($class, %arg) = @_;

   EV::signal $arg{signal}, $arg{cb}
}

sub child {
   my ($class, %arg) = @_;

   my $cb = $arg{cb};

   EV::child $arg{pid}, 0, sub {
      $cb->($_[0]->rpid, $_[0]->rstatus);
   }
}

sub idle {
   my ($class, %arg) = @_;

   EV::idle $arg{cb}
}

sub _poll {
   EV::run EV::RUN_ONCE;
}

sub AnyEvent::CondVar::Base::_wait {
   EV::run EV::RUN_ONCE until exists $_[0]{_ae_sent};
}

#sub loop {
#   EV::run;
#}

=head1 SEE ALSO

L<AnyEvent>, L<EV>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

