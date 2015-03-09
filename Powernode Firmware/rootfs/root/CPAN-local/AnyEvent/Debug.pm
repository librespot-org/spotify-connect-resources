=head1 NAME

AnyEvent::Debug - debugging utilities for AnyEvent

=head1 SYNOPSIS

   use AnyEvent::Debug;

   # create an interactive shell into the program
   my $shell = AnyEvent::Debug::shell "unix/", "/home/schmorp/myshell";
   # then on the shell: "socat readline /home/schmorp/myshell"

=head1 DESCRIPTION

This module provides functionality hopefully useful for debugging.

At the moment, "only" an interactive shell is implemented. This shell
allows you to interactively "telnet into" your program and execute Perl
code, e.g. to look at global variables.

=head1 FUNCTIONS

=over 4

=cut

package AnyEvent::Debug;

use B ();
use Carp ();
use Errno ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();
use AnyEvent::Socket ();
use AnyEvent::Log ();

our $TRACE = 1; # trace status

our ($TRACE_LOGGER, $TRACE_ENABLED);

# cache often-used strings, purely to save memory, at the expense of speed
our %STRCACHE;

=item $shell = AnyEvent::Debug::shell $host, $service

This function binds on the given host and service port and returns a
shell object, which determines the lifetime of the shell. Any number
of conenctions are accepted on the port, and they will give you a very
primitive shell that simply executes every line you enter.

All commands will be executed "blockingly" with the socket C<select>ed for
output. For a less "blocking" interface see L<Coro::Debug>.

The commands will be executed in the C<AnyEvent::Debug::shell> package,
which currently has "help" and a few other commands, and can be freely
modified by all shells. Code is evaluated under C<use strict 'subs'>.

Every shell has a logging context (C<$LOGGER>) that is attached to
C<$AnyEvent::Log::COLLECT>), which is especially useful to gether debug
and trace messages.

As a general programming guide, consider the beneficial aspects of
using more global (C<our>) variables than local ones (C<my>) in package
scope: Earlier all my modules tended to hide internal variables inside
C<my> variables, so users couldn't accidentally access them. Having
interactive access to your programs changed that: having internal
variables still in the global scope means you can debug them easier.

As no authentication is done, in most cases it is best not to use a TCP
port, but a unix domain socket, whcih can be put wherever you can access
it, but not others:

   our $SHELL = AnyEvent::Debug::shell "unix/", "/home/schmorp/shell";

Then you can use a tool to connect to the shell, such as the ever
versatile C<socat>, which in addition can give you readline support:

   socat readline /home/schmorp/shell
   # or:
   cd /home/schmorp; socat readline unix:shell

Socat can even give you a persistent history:

   socat readline,history=.anyevent-history unix:shell

Binding on C<127.0.0.1> (or C<::1>) might be a less secure but sitll not
totally insecure (on single-user machines) alternative to let you use
other tools, such as telnet:

   our $SHELL = AnyEvent::Debug::shell "127.1", "1357";

And then:

   telnet localhost 1357

=cut

sub shell($$) {
   local $TRACE = 0;

   AnyEvent::Socket::tcp_server $_[0], $_[1], sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "Welcome, $host:$port, use 'help' for more info!\015\012> ";
      my $rbuf;

      my $logger = new AnyEvent::Log::Ctx
         log_cb => sub {
            syswrite $fh, shift;
            0
         };

      my $logger_guard = AnyEvent::Util::guard {
         $AnyEvent::Log::COLLECT->detach ($logger);
      };
      $AnyEvent::Log::COLLECT->attach ($logger);

      local $TRACE = 0;
      my $rw; $rw = AE::io $fh, 0, sub {
         my $len = sysread $fh, $rbuf, 1024, length $rbuf;

         $logger_guard if 0; # reference it

         if (defined $len ? $len == 0 : $! != Errno::EAGAIN) {
            undef $rw;
         } else {
            while ($rbuf =~ s/^(.*)\015?\012//) {
               my $line = $1;

               AnyEvent::Util::fh_nonblocking $fh, 0;

               if ($line =~ /^\s*exit\b/) {
                  syswrite $fh, "sorry, no... if you want to execute exit, try CORE::exit.\015\012";
               } else {
                  package AnyEvent::Debug::shell;

                  no strict 'vars';
                  local $LOGGER = $logger;
                  my $old_stdout = select $fh;
                  local $| = 1;

                  my @res = eval $line;

                  select $old_stdout;
                  syswrite $fh, "$@" if $@;
                  syswrite $fh, "\015\012";

                  if (@res > 1) {
                     syswrite $fh, "$_: $res[$_]\015\012" for 0 .. $#res;
                  } elsif (@res == 1) {
                     syswrite $fh, "$res[0]\015\012";
                  }
               }

               syswrite $fh, "> ";
               AnyEvent::Util::fh_nonblocking $fh, 1;
            }
         }
      };
   }
}

{
   package AnyEvent::Debug::shell;

   our $LOGGER;

   sub help() {
      <<EOF
help         this command
wr [level]   sets wrap level to level (or toggles if missing)
v [level]    sets verbosity (or toggles between 0 and 9 if missing)
wl 'regex'   print wrapped watchers matching the regex (or all if missing)
i id,...     prints the watcher with the given ids in more detail
t            enable tracing for newly created watchers (enabled by default)
ut           disable tracing for newly created watchers
t  id,...    enable tracing for the given watcher (enabled by default)
ut id,...    disable tracing for the given weatcher
w id,...     converts the watcher ids to watcher objects (for scripting)
EOF
   }

   sub wl(;$) {
      my $re = @_ ? qr<$_[0]>i : qr<.>;

      my %res;

      while (my ($k, $v) = each %AnyEvent::Debug::Wrapped) {
         my $s = "$v";
         $res{$s} = $k . (exists $v->{error} ? "*" : " ")
            if $s =~ $re;
      }

      join "", map "$res{$_} $_\n", sort keys %res
   }

   sub w {
      map {
         $AnyEvent::Debug::Wrapped{$_} || do {
            print "$_: no such wrapped watcher.\n";
            ()
         }
      } @_
   }

   sub i {
      join "",
         map $_->id . " $_\n" . $_->verbose . "\n",
            &w
   }

   sub wr {
      AnyEvent::Debug::wrap (@_);

      "wrap level now $AnyEvent::Debug::WRAP_LEVEL"
   }

   sub t {
      if (@_) {
         @_ = &w;
         $_->trace (1)
            for @_;
         "tracing enabled for @_."
      } else {
         $AnyEvent::Debug::TRACE = 1;
         "tracing for newly created watchers is now enabled."
      }
   }

   sub u {
      if (@_) {
         @_ = &w;
         $_->trace (0)
            for @_;
         "tracing disabled for @_."
      } else {
         $AnyEvent::Debug::TRACE = 0;
         "tracing for newly created watchers is now disabled."
      }
   }

   sub v {
      $LOGGER->level (@_ ? $_[0] : $LOGGER->[1] ? 0 : 9);

      "verbose logging is now " . ($LOGGER->[1] ? "enabled" : "disabled") . "."
   }
}

=item AnyEvent::Debug::wrap [$level]

Sets the instrumenting/wrapping level of all watchers that are being
created after this call. If no C<$level> has been specified, then it
toggles between C<0> and C<1>.

The default wrap level is C<0>, or whatever
C<$ENV{PERL_ANYEVENT_DEBUG_WRAP}> specifies.

A level of C<0> disables wrapping, i.e. AnyEvent works normally, and in
its most efficient mode.

A level of C<1> or higher enables wrapping, which replaces all watchers
by AnyEvent::Debug::Wrapped objects, stores the location where a
watcher was created and wraps the callback to log all invocations at
"trace" loglevel if tracing is enabled fore the watcher. The initial
state of tracing when creating a watcher is taken from the global
variable C<$AnyEvent:Debug::TRACE>. The default value of that variable
is C<1>, but it can make sense to set it to C<0> and then do C<< local
$AnyEvent::Debug::TRACE = 1 >> in a block where you create "interesting"
watchers. Tracing can also be enabled and disabled later by calling the
watcher's C<trace> method.

The wrapper will also count how many times the callback was invoked and
will record up to ten runtime errors with corresponding backtraces. It
will also log runtime errors at "error" loglevel.

To see the trace messages, you can invoke your program with
C<PERL_ANYEVENT_VERBOSE=9>, or you can use AnyEvent::Log to divert
the trace messages in any way you like (the EXAMPLES section in
L<AnyEvent::Log> has some examples).

A level of C<2> does everything that level C<1> does, but also stores a
full backtrace of the location the watcher was created, which slows down
watcher creation considerably.

Every wrapped watcher will be linked into C<%AnyEvent::Debug::Wrapped>,
with its address as key. The C<wl> command in the debug shell can be used
to list watchers.

Instrumenting can increase the size of each watcher multiple times, and,
especially when backtraces are involved, also slows down watcher creation
a lot.

Also, enabling and disabling instrumentation will not recover the full
performance that you had before wrapping (the AE::xxx functions will stay
slower, for example).

If you are developing your program, also consider using AnyEvent::Strict
to check for common mistakes.

=cut

our $WRAP_LEVEL;
our $TRACE_CUR;
our $POST_DETECT;

sub wrap(;$) {
   my $PREV_LEVEL = $WRAP_LEVEL;
   $WRAP_LEVEL = @_ ? 0+shift : $WRAP_LEVEL ? 0 : 1;

   if ($AnyEvent::MODEL) {
      if ($WRAP_LEVEL && !$PREV_LEVEL) {
         $TRACE_LOGGER = AnyEvent::Log::logger trace => \$TRACE_ENABLED;
         AnyEvent::_isa_hook 0 => "AnyEvent::Debug::Wrap", 1;
         AnyEvent::Debug::Wrap::_reset ();
      } elsif (!$WRAP_LEVEL && $PREV_LEVEL) {
         AnyEvent::_isa_hook 0 => undef;
      }
   } else {
      $POST_DETECT ||= AnyEvent::post_detect {
         undef $POST_DETECT;
         return unless $WRAP_LEVEL;

         (my $level, $WRAP_LEVEL) = ($WRAP_LEVEL, undef);

         require AnyEvent::Strict unless $AnyEvent::Strict::VERSION;

         AnyEvent::post_detect { # make sure we run after AnyEvent::Strict
            wrap ($level);
         };
      };
   }
}

=item AnyEvent::Debug::path2mod $path

Tries to replace a path (e.g. the file name returned by caller)
by a module name. Returns the path unchanged if it fails.

Example:

   print AnyEvent::Debug::path2mod "/usr/lib/perl5/AnyEvent/Debug.pm";
   # might print "AnyEvent::Debug"

=cut

sub path2mod($) {
   keys %INC; # reset iterator

   while (my ($k, $v) = each %INC) {
      if ($_[0] eq $v) {
         $k =~ s%/%::%g if $k =~ s/\.pm$//;
         return $k;
      }
   }

   my $path = shift;

   $path =~ s%^\./%%;

   $path
}

=item AnyEvent::Debug::cb2str $cb

Using various gambits, tries to convert a callback (e.g. a code reference)
into a more useful string.

Very useful if you debug a program and have some callback, but you want to
know where in the program the callback is actually defined.

=cut

sub cb2str($) {
   my $cb = shift;

   "CODE" eq ref $cb
      or return "$cb";

   eval {
      my $cv = B::svref_2object ($cb);

      my $gv = $cv->GV
         or return "$cb";

      my $name = $gv->NAME;

      return (AnyEvent::Debug::path2mod $gv->FILE) . ":" . $gv->LINE
         if $name eq "__ANON__";

      $gv->STASH->NAME . "::" . $name;
   } || "$cb"
}

sub sv2str($) {
   if (ref $_[0]) {
      if (ref $_[0] eq "CODE") {
         return "$_[0]=" . cb2str $_[0];
      } else {
         return "$_[0]";
      }
   } else {
      for ("\'$_[0]\'") { # make copy
         substr $_, $Carp::MaxArgLen, length, "'..."
            if length > $Carp::MaxArgLen;
         return $_;
      }
   }
}

=item AnyEvent::Debug::backtrace [$skip]

Creates a backtrace (actually an AnyEvent::Debug::Backtrace object
that you can stringify), not unlike the Carp module would. Unlike the
Carp module it resolves some references (such as callbacks) to more
user-friendly strings, has a more succinct output format and most
importantly: doesn't leak memory like hell.

The reason it creates an object is to save time, as formatting can be
done at a later time. Still, creating a backtrace is a relatively slow
operation.

=cut

sub backtrace(;$) {
   my $w = shift;

   my (@bt, @c);
   my ($modlen, $sub);

   for (;;) {
      #         0          1      2            3         4           5          6            7       8         9         10
      # ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash)
      package DB;
      @c = caller $w++
         or last;
      package AnyEvent::Debug; # no block for speed reasons

      if ($c[7]) {
         $sub = "require $c[6]";
      } elsif (defined $c[6]) {
         $sub = "eval \"\"";
      } else {
         $sub = ($c[4] ? "" : "&") . $c[3];

         $sub .= "("
                 . (join ",",
                       map sv2str $DB::args[$_],
                          0 .. (@DB::args < $Carp::MaxArgNums ? @DB::args : $Carp::MaxArgNums) - 1)
                 . ")"
            if $c[4];
      }

      push @bt, [\($STRCACHE{$c[1]} ||= $c[1]), $c[2], $sub];
   }

   @DB::args = ();

   bless \@bt, "AnyEvent::Debug::Backtrace"
}

=back

=cut

package AnyEvent::Debug::Wrap;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use Scalar::Util ();
use Carp ();

sub _reset {
   for my $name (qw(io timer signal child idle)) {
      my $super = "SUPER::$name";

      *$name = sub {
         my ($self, %arg) = @_;

         my $w;

         my $t = $TRACE;

         my ($pkg, $file, $line, $sub);
         
         $w = 0;
         do {
            ($pkg, $file, $line) = caller $w++;
         } while $pkg =~ /^(?:AE|AnyEvent::(?:Socket|Handle|Util|Debug|Strict|Base|CondVar|CondVar::Base|Impl::.*)|Coro::AnyEvent::CondVar)$/;

         $sub = (caller $w)[3];

         my $cb = $arg{cb};
         $arg{cb} = sub {
            ++$w->{called};

            local $TRACE_CUR = $w;

            $TRACE_LOGGER->("enter $w") if $TRACE_ENABLED && $t;
            eval {
               local $SIG{__DIE__} = sub {
                  die $_[0] . AnyEvent::Debug::backtrace
                     if defined $^S;
               };
               &$cb;
            };
            if ($@) {
               my $err = "$@";
               push @{ $w->{error} }, [AE::now, $err]
                  if @{ $w->{error} } < 10;
               AE::log die => "($w) $err"
                  or warn "($w) $err";
            }
            $TRACE_LOGGER->("leave $w") if $TRACE_ENABLED && $t;
         };

         $self = bless {
            type   => $name,
            w      => $self->$super (%arg),
            rfile  => \($STRCACHE{$file} ||= $file),
            line   => $line,
            sub    => $sub,
            cur    => "$TRACE_CUR",
            now    => AE::now,
            arg    => \%arg,
            cb     => $cb,
            called => 0,
            rt     => \$t,
         }, "AnyEvent::Debug::Wrapped";

         delete $arg{cb};

         $self->{bt} = AnyEvent::Debug::backtrace 1
            if $WRAP_LEVEL >= 2;

         Scalar::Util::weaken ($w = $self);
         Scalar::Util::weaken ($AnyEvent::Debug::Wrapped{Scalar::Util::refaddr $self} = $self);

         $TRACE_LOGGER->("creat $w") if $TRACE_ENABLED && $t;

         $self
      };
   }
}

package AnyEvent::Debug::Wrapped;

=head1 THE AnyEvent::Debug::Wrapped CLASS

All watchers created while the wrap level is non-zero will be wrapped
inside an AnyEvent::Debug::Wrapped object. The address of the
wrapped watcher will become its ID - every watcher will be stored in
C<$AnyEvent::Debug::Wrapped{$id}>.

These wrapper objects can be stringified and have some methods defined on
them.

For debugging, of course, it can be helpful to look into these objects,
which is why this is documented here, but this might change at any time in
future versions.

Each object is a relatively standard hash with the following members:

   type   => name of the method used ot create the watcher (e.g. C<io>, C<timer>).
   w      => the actual watcher
   rfile  => reference to the filename of the file the watcher was created in
   line   => line number where it was created
   sub    => function name (or a special string) which created the watcher
   cur    => if created inside another watcher callback, this is the string rep of the other watcher
   now    => the timestamp (AE::now) when the watcher was created
   arg    => the arguments used to create the watcher (sans C<cb>)
   cb     => the original callback used to create the watcher
   called => the number of times the callback was called

Each object supports the following mehtods (warning: these are only
available on wrapped watchers, so are best for interactive use via the
debug shell).

=over 4

=cut

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use overload
   '""'     => sub {
      $_[0]{str} ||= do {
         my ($pkg, $line) = @{ $_[0]{caller} };

         my $mod = AnyEvent::Debug::path2mod ${ $_[0]{rfile} };
         my $sub = $_[0]{sub};

         if (defined $sub) {
            $sub =~ s/^\Q$mod\E:://;
            $sub = "($sub)";
         }

         "$mod:$_[0]{line}$sub>$_[0]{type}>"
         . (AnyEvent::Debug::cb2str $_[0]{cb})
      };
   },
   fallback => 1,
;

=item $w->id

Returns the numerical id of the watcher, as used in the debug shell.

=cut

sub id {
   Scalar::Util::refaddr shift
}

=item $w->verbose

Returns a multiline textual description of the watcher, including the
first ten exceptions caught while executing the callback.

=cut

sub verbose {
   my ($self) = @_;

   my $res = "type:    $self->{type} watcher\n"
           . "args:    " . (join " ", %{ $self->{arg} }) . "\n" # TODO: decode fh?
           . "created: " . (AnyEvent::Log::ft $self->{now}) . " ($self->{now})\n"
           . "file:    ${ $self->{rfile} }\n"
           . "line:    $self->{line}\n"
           . "subname: $self->{sub}\n"
           . "context: $self->{cur}\n"
           . "tracing: " . (${ $self->{rt} } ? "enabled" : "disabled") . "\n"
           . "cb:      $self->{cb} (" . (AnyEvent::Debug::cb2str $self->{cb}) . ")\n"
           . "invoked: $self->{called} times\n";

   if (exists $self->{bt}) {
      $res .= "created\n$self->{bt}";
   }

   if (exists $self->{error}) {
      $res .= "errors:   " . @{$self->{error}} . "\n";

      $res .= "error: " . (AnyEvent::Log::ft $_->[0]) . " ($_->[0]) $_->[1]\n"
         for @{$self->{error}};
   }

   $res
}

=item $w->trace ($on)

Enables (C<$on> is true) or disables (C<$on> is false) tracing on this
watcher.

To get tracing messages, both the global logging settings must have trace
messages enabled for the context C<AnyEvent::Debug> and tracing must be
enabled for the wrapped watcher.

To enable trace messages globally, the simplest way is to start the
program with C<PERL_ANYEVENT_VERBOSE=9> in the environment.

Tracing for each individual watcher is enabled by default (unless
C<$AnyEvent::Debug::TRACE> has been set to false).

=cut

sub trace {
   ${ $_[0]{rt} } = $_[1];
}

sub DESTROY {
   $TRACE_LOGGER->("dstry $_[0]") if $TRACE_ENABLED && ${ $_[0]{rt} };

   delete $AnyEvent::Debug::Wrapped{Scalar::Util::refaddr $_[0]};
}

=back

=cut

package AnyEvent::Debug::Backtrace;

use AnyEvent (); BEGIN { AnyEvent::common_sense }

sub as_string {
   my ($self) = @_;

   my @bt;
   my $modlen;

   for (@$self) {
      my ($rpath, $line, $sub) = @$_;

      $rpath = (AnyEvent::Debug::path2mod $$rpath) . " line $line";
      $modlen = length $rpath if $modlen < length $rpath;

      $sub =~ s/\r/\\r/g;
      $sub =~ s/\n/\\n/g;
      $sub =~ s/([\x00-\x1f\x7e-\xff])/sprintf "\\x%02x", ord $1/ge;
      $sub =~ s/([^\x20-\x7e])/sprintf "\\x{%x}", ord $1/ge;

      push @bt, [$rpath, $sub];
   }

   join "",
      map { sprintf "%*s %s\n", -$modlen, $_->[0], $_->[1] }
         @bt
}

use overload
   '""'     => \&as_string,
   fallback => 1,
;

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

