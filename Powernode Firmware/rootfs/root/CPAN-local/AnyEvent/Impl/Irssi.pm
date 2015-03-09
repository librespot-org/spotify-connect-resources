=head1 NAME

AnyEvent::Impl::Irssi - AnyEvent adaptor for Irssi

=head1 SYNOPSIS

   use AnyEvent;
  
   # this module gets loaded automatically when running under irssi

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make Irssi scripts work with AnyEvent.

Limitations of this backend and implementation details:

=over 4

=item * This backend does not support blocking waits.

That means you must set a callback on any condvars, or otherwise make sure
to never call C<recv> on a condvar that hasn't been signalled yet.

=item * Child exits will be handled by AnyEvent.

AnyEvent will take over child handling, as Irssi only polls for children
once/second and cannot handle unspecific child watchers.

This I<should> have no negative effect, as AnyEvent will emit a pidwait
signal just like irssi itself would.

=item * Artificial timer delays.

Irssi artificially enforces timers to have at least a 10ms delay (by
croaking, even).

This means that some applications will be limited to a rate of 100Hz (for
example, L<Coro::AnyEvent> thread scheduling).

=item * Irssi leaks memory like hell.

Yeah.

=back

Apart from that, documentation is notoriously wrong (e.g. file handles
are not supported by C<input_add>, contrary to documentation), hooking
into irssi has to be done in... weird... ways, but otherwise, Irssi is
surprisingly full-featured (for basically being a hack).

=cut

package AnyEvent::Impl::Irssi;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Carp ();
use Irssi ();

our @ISA;

# irssi works only from certain namespaces, so we
# create one and use it.
sub init {
   my $pkg = caller;

   push @ISA, $pkg;

   local $/;
   eval "package $pkg; " . <DATA>;
   print "AnyEvent::Impl::Irssi fatal compilation error: $@" if $@;

   close DATA;
}

Irssi::command "/script exec -permanent AnyEvent::Impl::Irssi::init 'AnyEvent adaptor'";

1;

__DATA__

BEGIN { AnyEvent::common_sense }
use base "AnyEvent::Base";

sub io {
   my ($class, %arg) = @_;
   
   my $cb = $arg{cb};
   my $fd = fileno $arg{fh};
   defined $fd or $fd = $arg{fh};

   my $source = Irssi::input_add
      $fd,
      $arg{poll} eq "r" ? Irssi::INPUT_READ : Irssi::INPUT_WRITE,
      $cb,
      undef;

   bless \\$source, "AnyEvent::Impl::Irssi::io"
}

sub AnyEvent::Impl::Irssi::io::DESTROY {
   Irssi::input_remove $${$_[0]};
}

sub timer {
   my ($class, %arg) = @_;
   
   my $cb    = $arg{cb};
   my $ival  = $arg{interval} * 1000;
   my $after = $arg{after} * 1000;

   my $source; $source = Irssi::timeout_add_once $after > 10 ? $after : 10,
      ($ival ? sub {
                 $source = Irssi::timeout_add $ival > 10 ? $ival : 10, $cb, undef;
                 &$cb;
                 0
               }
             : $cb),
      undef;

   bless \\$source, "AnyEvent::Impl::Irssi::timer"
}

sub AnyEvent::Impl::Irssi::timer::DESTROY {
   Irssi::timeout_remove $${$_[0]};
}

my $_pidwait = sub {
   my ($rpid, $rstatus) = @_;

   AnyEvent::Base->_emit_childstatus ($rpid, $rstatus);
};

Irssi::signal_add pidwait => $_pidwait;

sub _emit_childstatus {
   my ($self, $rpid, $rstatus) = @_;
   $self->SUPER::_emit_childstatus ($rpid, $rstatus);

   Irssi::signal_remove pidwait => $_pidwait;
   Irssi::signal_emit   pidwait => $rpid+0, $rstatus+0;
   Irssi::signal_add    pidwait => $_pidwait;
}

#sub loop {
#   Carp::croak "Irssi does not support blocking waits";
#}

=head1 SEE ALSO

L<AnyEvent>, L<Irssi>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

