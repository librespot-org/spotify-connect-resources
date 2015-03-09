=head1 NAME

AnyEvent::Strict - force strict mode on for the whole process

=head1 SYNOPSIS

   use AnyEvent::Strict;
   # strict mode now switched on

=head1 DESCRIPTION

This module implements AnyEvent's strict mode.

Loading it makes AnyEvent check all arguments to AnyEvent-methods, at the
expense of being slower (often the argument checking takes longer than the
actual function). It also wraps all callbacks to check for modifications
of C<$_>, which indicates a programming bug inside the watcher callback.

Normally, you don't load this module yourself but instead use it
indirectly via the C<PERL_ANYEVENT_STRICT> environment variable (see
L<AnyEvent>). However, this module can be loaded manually at any time.

=cut

package AnyEvent::Strict;

use Carp qw(croak);
use Errno ();
use POSIX ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }

AnyEvent::_isa_hook 1 => "AnyEvent::Strict", 1;

BEGIN {
   if (defined &Internals::SvREADONLY) {
      # readonly available (at least 5.8.9+, working better in 5.10.1+)
      *wrap = sub {
         my $cb = shift;

         sub {
            local $_;
            Internals::SvREADONLY $_, 1;
            &$cb;
         }
      };
   } else {
      # or not :/
      my $magic = []; # a unique magic value

      *wrap = sub {
         my $cb = shift;

         sub {
            local $_ = $magic;

            &$cb;

            if (!ref $_ || $_ != $magic) {
               require AnyEvent::Debug;
               die "callback $cb (" . AnyEvent::Debug::cb2str ($cb) . ") modified \$_ without restoring it.\n";
            }
         }
      };
   }
}

our (@FD_INUSE, $FD_I);
our $FD_CHECK_W = AE::timer 4, 4, sub {
   my $cnt = (@FD_INUSE < 100 * 10 ? int @FD_INUSE * 0.1 : 100) || 10;

   if ($FD_I <= 0) {
      #pop @FD_INUSE while @FD_INUSE && !$FD_INUSE[-1];
      $FD_I = @FD_INUSE
         or return; # empty
   }

   $cnt = $FD_I if $cnt > $FD_I;

   eval {
      do {
         !$FD_INUSE[--$FD_I]
            or (POSIX::lseek $FD_I, 0, 1) != -1
            or $! != Errno::EBADF
            or die;
      } while --$cnt;
      1
   } or AE::log crit => "File descriptor $FD_I registered with AnyEvent but prematurely closed, event loop might malfunction.";
};

sub io {
   my $class = shift;
   my (%arg, $fh, $cb, $fd) = @_;

   ref $arg{cb}
      or croak "AnyEvent->io called with illegal cb argument '$arg{cb}'";
   $cb = wrap delete $arg{cb};
 
   $arg{poll} =~ /^[rw]$/
      or croak "AnyEvent->io called with illegal poll argument '$arg{poll}'";

   $fh = delete $arg{fh};

   if ($fh =~ /^\s*\d+\s*$/) {
      $fd = $fh;
      $fh = AnyEvent::_dupfh $arg{poll}, $fh;
   } else {
      defined eval { $fd = fileno $fh }
         or croak "AnyEvent->io called with illegal fh argument '$fh'";
   }

   -f $fh
      and croak "AnyEvent->io called with fh argument pointing to a file";

   delete $arg{poll};
 
   croak "AnyEvent->io called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   ++$FD_INUSE[$fd];

   bless [
      $fd,
      $class->SUPER::io (@_, cb => $cb)
   ], "AnyEvent::Strict::io";
}

sub AnyEvent::Strict::io::DESTROY {
   --$FD_INUSE[$_[0][0]];
}

sub timer {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->timer called with illegal cb argument '$arg{cb}'";
   my $cb = wrap delete $arg{cb};
 
   exists $arg{after}
      or croak "AnyEvent->timer called without mandatory 'after' parameter";
   delete $arg{after};
 
   !$arg{interval} or $arg{interval} > 0
      or croak "AnyEvent->timer called with illegal interval argument '$arg{interval}'";
   delete $arg{interval};
 
   croak "AnyEvent->timer called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::timer (@_, cb => $cb)
}

sub signal {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->signal called with illegal cb argument '$arg{cb}'";
   my $cb = wrap delete $arg{cb};
 
   defined AnyEvent::Base::sig2num $arg{signal} and $arg{signal} == 0
      or croak "AnyEvent->signal called with illegal signal name '$arg{signal}'";
   delete $arg{signal};
 
   croak "AnyEvent->signal called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::signal (@_, cb => $cb)
}

sub child {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->child called with illegal cb argument '$arg{cb}'";
   my $cb = wrap delete $arg{cb};
 
   $arg{pid} =~ /^-?\d+$/
      or croak "AnyEvent->child called with malformed pid value '$arg{pid}'";
   delete $arg{pid};
 
   croak "AnyEvent->child called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::child (@_, cb => $cb)
}

sub idle {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->idle called with illegal cb argument '$arg{cb}'";
   my $cb = wrap delete $arg{cb};
 
   croak "AnyEvent->idle called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::idle (@_, cb => $cb)
}

sub condvar {
   my $class = shift;
   my %arg = @_;

   !exists $arg{cb} or ref $arg{cb}
      or croak "AnyEvent->condvar called with illegal cb argument '$arg{cb}'";
   my @cb = exists $arg{cb} ? (cb => wrap delete $arg{cb}) : ();
 
   croak "AnyEvent->condvar called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::condvar (@cb);
}

sub time {
   my $class = shift;

   @_
      and croak "AnyEvent->time wrongly called with paramaters";

   $class->SUPER::time (@_)
}

sub now {
   my $class = shift;

   @_
      and croak "AnyEvent->now wrongly called with paramaters";

   $class->SUPER::now (@_)
}

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

