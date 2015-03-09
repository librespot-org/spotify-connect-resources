=head1 NAME

AnyEvent::Log - simple logging "framework"

=head1 SYNOPSIS

Simple uses:

   use AnyEvent;

   AE::log fatal => "No config found, cannot continue!"; # never returns
   AE::log alert => "The battery died!";
   AE::log crit  => "The battery temperature is too hot!";
   AE::log error => "Division by zero attempted.";
   AE::log warn  => "Couldn't delete the file.";
   AE::log note  => "Wanted to create config, but config already exists.";
   AE::log info  => "File soandso successfully deleted.";
   AE::log debug => "the function returned 3";
   AE::log trace => "going to call function abc";

Log level overview:

   LVL NAME      SYSLOG   PERL  NOTE
    1  fatal     emerg    exit  system unusable, aborts program!
    2  alert                    failure in primary system
    3  critical  crit           failure in backup system
    4  error     err      die   non-urgent program errors, a bug
    5  warn      warning        possible problem, not necessarily error
    6  note      notice         unusual conditions
    7  info                     normal messages, no action required
    8  debug                    debugging messages for development
    9  trace                    copious tracing output

"Complex" uses (for speed sensitive code, e.g. trace/debug messages):

   use AnyEvent::Log;

   my $tracer = AnyEvent::Log::logger trace => \$my $trace;

   $tracer->("i am here") if $trace;
   $tracer->(sub { "lots of data: " . Dumper $self }) if $trace;

Configuration (also look at the EXAMPLES section):

   # set logging for the current package to errors and higher only
   AnyEvent::Log::ctx->level ("error");

   # set logging level to suppress anything below "notice"
   $AnyEvent::Log::FILTER->level ("notice");

   # send all critical and higher priority messages to syslog,
   # regardless of (most) other settings
   $AnyEvent::Log::COLLECT->attach (new AnyEvent::Log::Ctx
      level         => "critical",
      log_to_syslog => "user",
   );

=head1 DESCRIPTION

This module implements a relatively simple "logging framework". It doesn't
attempt to be "the" logging solution or even "a" logging solution for
AnyEvent - AnyEvent simply creates logging messages internally, and this
module more or less exposes the mechanism, with some extra spiff to allow
using it from other modules as well.

Remember that the default verbosity level is C<4> (C<error>), so only
errors and more important messages will be logged, unless you set
C<PERL_ANYEVENT_VERBOSE> to a higher number before starting your program
(C<AE_VERBOSE=5> is recommended during development), or change the logging
level at runtime with something like:

   use AnyEvent::Log;
   $AnyEvent::Log::FILTER->level ("info");

The design goal behind this module was to keep it simple (and small),
but make it powerful enough to be potentially useful for any module, and
extensive enough for the most common tasks, such as logging to multiple
targets, or being able to log into a database.

The module is also usable before AnyEvent itself is initialised, in which
case some of the functionality might be reduced.

The amount of documentation might indicate otherwise, but the runtime part
of the module is still just below 300 lines of code.

=head1 LOGGING LEVELS

Logging levels in this module range from C<1> (highest priority) to C<9>
(lowest priority). Note that the lowest numerical value is the highest
priority, so when this document says "higher priority" it means "lower
numerical value".

Instead of specifying levels by name you can also specify them by aliases:

   LVL NAME      SYSLOG   PERL  NOTE
    1  fatal     emerg    exit  system unusable, aborts program!
    2  alert                    failure in primary system
    3  critical  crit           failure in backup system
    4  error     err      die   non-urgent program errors, a bug
    5  warn      warning        possible problem, not necessarily error
    6  note      notice         unusual conditions
    7  info                     normal messages, no action required
    8  debug                    debugging messages for development
    9  trace                    copious tracing output

As you can see, some logging levels have multiple aliases - the first one
is the "official" name, the second one the "syslog" name (if it differs)
and the third one the "perl" name, suggesting (only!) that you log C<die>
messages at C<error> priority. The NOTE column tries to provide some
rationale on how to chose a logging level.

As a rough guideline, levels 1..3 are primarily meant for users of the
program (admins, staff), and are the only ones logged to STDERR by
default. Levels 4..6 are meant for users and developers alike, while
levels 7..9 are usually meant for developers.

You can normally only log a message once at highest priority level (C<1>,
C<fatal>), because logging a fatal message will also quit the program - so
use it sparingly :)

For example, a program that finds an unknown switch on the commandline
might well use a fatal logging level to tell users about it - the "system"
in this case would be the program, or module.

Some methods also offer some extra levels, such as C<0>, C<off>, C<none>
or C<all> - these are only valid for the methods that documented them.

=head1 LOGGING FUNCTIONS

The following functions allow you to log messages. They always use the
caller's package as a "logging context". Also, the main logging function,
C<log>, is aliased to C<AnyEvent::log> and C<AE::log> when the C<AnyEvent>
module is loaded.

=over 4

=cut

package AnyEvent::Log;

use Carp ();
use POSIX ();

# layout of a context
#       0       1         2        3        4,    5
# [$title, $level, %$slaves, &$logcb, &$fmtcb, $cap]

use AnyEvent (); BEGIN { AnyEvent::common_sense }
#use AnyEvent::Util (); need to load this in a delayed fashion, as it uses AE::log

our $VERSION = $AnyEvent::VERSION;

our ($COLLECT, $FILTER, $LOG);

our ($now_int, $now_str1, $now_str2);

# Format Time, not public - yet?
sub ft($) {
   my $i = int $_[0];
   my $f = sprintf "%06d", 1e6 * ($_[0] - $i);

   ($now_int, $now_str1, $now_str2) = ($i, split /\x01/, POSIX::strftime "%Y-%m-%d %H:%M:%S.\x01 %z", localtime $i)
      if $now_int != $i;

   "$now_str1$f$now_str2"
}

our %CTX; # all package contexts

# creates a default package context object for the given package
sub _pkg_ctx($) {
   my $ctx = bless [$_[0], (1 << 10) - 1 - 1, {}], "AnyEvent::Log::Ctx";

   # link "parent" package
   my $parent = $_[0] =~ /^(.+)::/
      ? $CTX{$1} ||= &_pkg_ctx ("$1")
      : $COLLECT;

   $ctx->[2]{$parent+0} = $parent;

   $ctx
}

=item AnyEvent::Log::log $level, $msg[, @args]

Requests logging of the given C<$msg> with the given log level, and
returns true if the message was logged I<somewhere>.

For loglevel C<fatal>, the program will abort.

If only a C<$msg> is given, it is logged as-is. With extra C<@args>, the
C<$msg> is interpreted as an sprintf format string.

The C<$msg> should not end with C<\n>, but may if that is convenient for
you. Also, multiline messages are handled properly.

Last not least, C<$msg> might be a code reference, in which case it is
supposed to return the message. It will be called only then the message
actually gets logged, which is useful if it is costly to create the
message in the first place.

This function takes care of saving and restoring C<$!> and C<$@>, so you
don't have to.

Whether the given message will be logged depends on the maximum log level
and the caller's package. The return value can be used to ensure that
messages or not "lost" - for example, when L<AnyEvent::Debug> detects a
runtime error it tries to log it at C<die> level, but if that message is
lost it simply uses warn.

Note that you can (and should) call this function as C<AnyEvent::log> or
C<AE::log>, without C<use>-ing this module if possible (i.e. you don't
need any additional functionality), as those functions will load the
logging module on demand only. They are also much shorter to write.

Also, if you optionally generate a lot of debug messages (such as when
tracing some code), you should look into using a logger callback and a
boolean enabler (see C<logger>, below).

Example: log something at error level.

   AE::log error => "something";

Example: use printf-formatting.

   AE::log info => "%5d %-10.10s %s", $index, $category, $msg;

Example: only generate a costly dump when the message is actually being logged.

   AE::log debug => sub { require Data::Dump; Data::Dump::dump \%cache };

=cut

# also allow syslog equivalent names
our %STR2LEVEL = (
   fatal    => 1, emerg    => 1, exit => 1,
   alert    => 2,
   critical => 3, crit     => 3,
   error    => 4, err      => 4, die  => 4,
   warn     => 5, warning  => 5,
   note     => 6, notice   => 6,
   info     => 7,
   debug    => 8,
   trace    => 9,
);

our $TIME_EXACT;

sub exact_time($) {
   $TIME_EXACT = shift;
   *_ts = $AnyEvent::MODEL
      ? $TIME_EXACT ? \&AE::now : \&AE::time
      : sub () { $TIME_EXACT ? do { require Time::HiRes; Time::HiRes::time () } : time };
}

BEGIN {
   exact_time 0;
}

AnyEvent::post_detect {
   exact_time $TIME_EXACT;
};

our @LEVEL2STR = qw(0 fatal alert crit error warn note info debug trace);

# time, ctx, level, msg
sub _format($$$$) {
   my $ts = ft $_[0];
   my $ct = " ";

   my @res;

   for (split /\n/, sprintf "%-5s %s: %s", $LEVEL2STR[$_[2]], $_[1][0], $_[3]) {
      push @res, "$ts$ct$_\n";
      $ct = " + ";
   }

   join "", @res
}

sub fatal_exit() {
   exit 1;
}

sub _log {
   my ($ctx, $level, $format, @args) = @_;

   $level = $level > 0 && $level <= 9
            ? $level+0
            : $STR2LEVEL{$level} || Carp::croak "$level: not a valid logging level, caught";

   my $mask = 1 << $level;

   my ($success, %seen, @ctx, $now, @fmt);

   do
      {
         # if !ref, then it's a level number
         if (!ref $ctx) {
            $level = $ctx;
         } elsif ($ctx->[1] & $mask and !$seen{$ctx+0}++) {
            # logging/recursing into this context

            # level cap
            if ($ctx->[5] > $level) {
               push @ctx, $level; # restore level when going up in tree
               $level = $ctx->[5];
            }

            # log if log cb
            if ($ctx->[3]) {
               # logging target found

               local ($!, $@);

               # now get raw message, unless we have it already
               unless ($now) {
                  $format = $format->() if ref $format;
                  $format = sprintf $format, @args if @args;
                  $format =~ s/\n$//;
                  $now = _ts;
               };

               # format msg
               my $str = $ctx->[4]
                  ? $ctx->[4]($now, $_[0], $level, $format)
                  : ($fmt[$level] ||= _format $now, $_[0], $level, $format);

               $success = 1;

               $ctx->[3]($str)
                  or push @ctx, values %{ $ctx->[2] }; # not consumed - propagate
            } else {
               push @ctx, values %{ $ctx->[2] }; # not masked - propagate
            }
         }
      }
   while $ctx = pop @ctx;

   fatal_exit if $level <= 1;

   $success
}

sub log($$;@) {
   _log
      $CTX{ (caller)[0] } ||= _pkg_ctx +(caller)[0],
      @_;
}

=item $logger = AnyEvent::Log::logger $level[, \$enabled]

Creates a code reference that, when called, acts as if the
C<AnyEvent::Log::log> function was called at this point with the given
level. C<$logger> is passed a C<$msg> and optional C<@args>, just as with
the C<AnyEvent::Log::log> function:

   my $debug_log = AnyEvent::Log::logger "debug";

   $debug_log->("debug here");
   $debug_log->("%06d emails processed", 12345);
   $debug_log->(sub { $obj->as_string });

The idea behind this function is to decide whether to log before actually
logging - when the C<logger> function is called once, but the returned
logger callback often, then this can be a tremendous speed win.

Despite this speed advantage, changes in logging configuration will
still be reflected by the logger callback, even if configuration changes
I<after> it was created.

To further speed up logging, you can bind a scalar variable to the logger,
which contains true if the logger should be called or not - if it is
false, calling the logger can be safely skipped. This variable will be
updated as long as C<$logger> is alive.

Full example:

   # near the init section
   use AnyEvent::Log;

   my $debug_log = AnyEvent:Log::logger debug => \my $debug;

   # and later in your program
   $debug_log->("yo, stuff here") if $debug;

   $debug and $debug_log->("123");

=cut

our %LOGGER;

# re-assess logging status for all loggers
sub _reassess {
   local $SIG{__DIE__};
   my $die = sub { die };

   for (@_ ? $LOGGER{$_[0]} : values %LOGGER) {
      my ($ctx, $level, $renabled) = @$_;

      # to detect whether a message would be logged, we actually
      # try to log one and die. this isn't fast, but we can be
      # sure that the logging decision is correct :)

      $$renabled = !eval {
         _log $ctx, $level, $die;

         1
      };
   }
}

sub _logger {
   my ($ctx, $level, $renabled) = @_;

   $$renabled = 1;

   my $logger = [$ctx, $level, $renabled];

   $LOGGER{$logger+0} = $logger;

   _reassess $logger+0;

   require AnyEvent::Util unless $AnyEvent::Util::VERSION;
   my $guard = AnyEvent::Util::guard (sub {
      # "clean up"
      delete $LOGGER{$logger+0};
   });

   sub {
      $guard if 0; # keep guard alive, but don't cause runtime overhead

      _log $ctx, $level, @_
         if $$renabled;
   }
}

sub logger($;$) {
   _logger
      $CTX{ (caller)[0] } ||= _pkg_ctx +(caller)[0],
      @_
}

=item AnyEvent::Log::exact_time $on

By default, C<AnyEvent::Log> will use C<AE::now>, i.e. the cached
eventloop time, for the log timestamps. After calling this function with a
true value it will instead resort to C<AE::time>, i.e. fetch the current
time on each log message. This only makes a difference for event loops
that actually cache the time (such as L<EV> or L<AnyEvent::Loop>).

This setting can be changed at any time by calling this function.

Since C<AnyEvent::Log> has to work even before the L<AnyEvent> has been
initialised, this switch will also decide whether to use C<CORE::time> or
C<Time::HiRes::time> when logging a message before L<AnyEvent> becomes
available.

=back

=head1 LOGGING CONTEXTS

This module associates every log message with a so-called I<logging
context>, based on the package of the caller. Every perl package has its
own logging context.

A logging context has three major responsibilities: filtering, logging and
propagating the message.

For the first purpose, filtering, each context has a set of logging
levels, called the log level mask. Messages not in the set will be ignored
by this context (masked).

For logging, the context stores a formatting callback (which takes the
timestamp, context, level and string message and formats it in the way
it should be logged) and a logging callback (which is responsible for
actually logging the formatted message and telling C<AnyEvent::Log>
whether it has consumed the message, or whether it should be propagated).

For propagation, a context can have any number of attached I<slave
contexts>. Any message that is neither masked by the logging mask nor
masked by the logging callback returning true will be passed to all slave
contexts.

Each call to a logging function will log the message at most once per
context, so it does not matter (much) if there are cycles or if the
message can arrive at the same context via multiple paths.

=head2 DEFAULTS

By default, all logging contexts have an full set of log levels ("all"), a
disabled logging callback and the default formatting callback.

Package contexts have the package name as logging title by default.

They have exactly one slave - the context of the "parent" package. The
parent package is simply defined to be the package name without the last
component, i.e. C<AnyEvent::Debug::Wrapped> becomes C<AnyEvent::Debug>,
and C<AnyEvent> becomes ... C<$AnyEvent::Log::COLLECT> which is the
exception of the rule - just like the "parent" of any single-component
package name in Perl is C<main>, the default slave of any top-level
package context is C<$AnyEvent::Log::COLLECT>.

Since perl packages form only an approximate hierarchy, this slave
context can of course be removed.

All other (anonymous) contexts have no slaves and an empty title by
default.

When the module is loaded it creates the C<$AnyEvent::Log::LOG> logging
context that simply logs everything via C<warn>, without propagating
anything anywhere by default.  The purpose of this context is to provide
a convenient place to override the global logging target or to attach
additional log targets. It's not meant for filtering.

It then creates the C<$AnyEvent::Log::FILTER> context whose
purpose is to suppress all messages with priority higher
than C<$ENV{PERL_ANYEVENT_VERBOSE}>. It then attached the
C<$AnyEvent::Log::LOG> context to it. The purpose of the filter context
is to simply provide filtering according to some global log level.

Finally it creates the top-level package context C<$AnyEvent::Log::COLLECT>
and attaches the C<$AnyEvent::Log::FILTER> context to it, but otherwise
leaves it at default config. Its purpose is simply to collect all log
messages system-wide.

The hierarchy is then:

   any package, eventually -> $COLLECT -> $FILTER -> $LOG

The effect of all this is that log messages, by default, wander up to the
C<$AnyEvent::Log::COLLECT> context where all messages normally end up,
from there to C<$AnyEvent::Log::FILTER> where log messages with lower
priority then C<$ENV{PERL_ANYEVENT_VERBOSE}> will be filtered out and then
to the C<$AnyEvent::Log::LOG> context to be passed to C<warn>.

This makes it easy to set a global logging level (by modifying $FILTER),
but still allow other contexts to send, for example, their debug and trace
messages to the $LOG target despite the global logging level, or to attach
additional log targets that log messages, regardless of the global logging
level.

It also makes it easy to modify the default warn-logger ($LOG) to
something that logs to a file, or to attach additional logging targets
(such as loggign to a file) by attaching it to $FILTER.

=head2 CREATING/FINDING/DESTROYING CONTEXTS

=over 4

=item $ctx = AnyEvent::Log::ctx [$pkg]

This function creates or returns a logging context (which is an object).

If a package name is given, then the context for that packlage is
returned. If it is called without any arguments, then the context for the
callers package is returned (i.e. the same context as a C<AE::log> call
would use).

If C<undef> is given, then it creates a new anonymous context that is not
tied to any package and is destroyed when no longer referenced.

=cut

sub ctx(;$) {
   my $pkg = @_ ? shift : (caller)[0];

   ref $pkg
      ? $pkg
      : defined $pkg
         ? $CTX{$pkg} ||= AnyEvent::Log::_pkg_ctx $pkg
         : bless [undef, (1 << 10) - 1 - 1], "AnyEvent::Log::Ctx"
}

=item AnyEvent::Log::reset

Resets all package contexts and recreates the default hierarchy if
necessary, i.e. resets the logging subsystem to defaults, as much as
possible. This process keeps references to contexts held by other parts of
the program intact.

This can be used to implement config-file (re-)loading: before loading a
configuration, reset all contexts.

=cut

our $ORIG_VERBOSE = $AnyEvent::VERBOSE;
$AnyEvent::VERBOSE = 9;

sub reset {
   # hard to kill complex data structures
   # we "recreate" all package loggers and reset the hierarchy
   while (my ($k, $v) = each %CTX) {
      @$v = ($k, (1 << 10) - 1 - 1, { });

      $v->attach ($k =~ /^(.+)::/ ? $CTX{$1} : $AnyEvent::Log::COLLECT);
   }

   @$_ = ($_->[0], (1 << 10) - 1 - 1)
      for $LOG, $FILTER, $COLLECT;

   #$LOG->slaves;
   $LOG->title ('$AnyEvent::Log::LOG');
   $LOG->log_to_warn;

   $FILTER->slaves ($LOG);
   $FILTER->title ('$AnyEvent::Log::FILTER');
   $FILTER->level ($ORIG_VERBOSE);

   $COLLECT->slaves ($FILTER);
   $COLLECT->title ('$AnyEvent::Log::COLLECT');

   _reassess;
}

# override AE::log/logger
*AnyEvent::log    = *AE::log    = \&log;
*AnyEvent::logger = *AE::logger = \&logger;

# convert AnyEvent loggers to AnyEvent::Log loggers
$_->[0] = ctx $_->[0] # convert "pkg" to "ctx"
   for values %LOGGER;

# create the default logger contexts
$LOG     = ctx undef;
$FILTER  = ctx undef;
$COLLECT = ctx undef;

AnyEvent::Log::reset;

# hello, CPAN, please catch me
package AnyEvent::Log::LOG;
package AE::Log::LOG;
package AnyEvent::Log::FILTER;
package AE::Log::FILTER;
package AnyEvent::Log::COLLECT;
package AE::Log::COLLECT;

package AnyEvent::Log::Ctx;

=item $ctx = new AnyEvent::Log::Ctx methodname => param...

This is a convenience constructor that makes it simpler to construct
anonymous logging contexts.

Each key-value pair results in an invocation of the method of the same
name as the key with the value as parameter, unless the value is an
arrayref, in which case it calls the method with the contents of the
array. The methods are called in the same order as specified.

Example: create a new logging context and set both the default logging
level, some slave contexts and a logging callback.

   $ctx = new AnyEvent::Log::Ctx
      title   => "dubious messages",
      level   => "error",
      log_cb  => sub { print STDOUT shift; 0 },
      slaves  => [$ctx1, $ctx, $ctx2],
   ;

=back

=cut

sub new {
   my $class = shift;

   my $ctx = AnyEvent::Log::ctx undef;

   while (@_) {
      my ($k, $v) = splice @_, 0, 2;
      $ctx->$k (ref $v eq "ARRAY" ? @$v : $v);
   }

   bless $ctx, $class # do we really support subclassing, hmm?
}


=head2 CONFIGURING A LOG CONTEXT

The following methods can be used to configure the logging context.

=over 4

=item $ctx->title ([$new_title])

Returns the title of the logging context - this is the package name, for
package contexts, and a user defined string for all others.

If C<$new_title> is given, then it replaces the package name or title.

=cut

sub title {
   $_[0][0] = $_[1] if @_ > 1;
   $_[0][0]
}

=back

=head3 LOGGING LEVELS

The following methods deal with the logging level set associated with the
log context.

The most common method to use is probably C<< $ctx->level ($level) >>,
which configures the specified and any higher priority levels.

All functions which accept a list of levels also accept the special string
C<all> which expands to all logging levels.

=over 4

=item $ctx->levels ($level[, $level...)

Enables logging for the given levels and disables it for all others.

=item $ctx->level ($level)

Enables logging for the given level and all lower level (higher priority)
ones. In addition to normal logging levels, specifying a level of C<0> or
C<off> disables all logging for this level.

Example: log warnings, errors and higher priority messages.

   $ctx->level ("warn");
   $ctx->level (5); # same thing, just numeric

=item $ctx->enable ($level[, $level...])

Enables logging for the given levels, leaving all others unchanged.

=item $ctx->disable ($level[, $level...])

Disables logging for the given levels, leaving all others unchanged.

=item $ctx->cap ($level)

Caps the maximum priority to the given level, for all messages logged
to, or passing through, this context. That is, while this doesn't affect
whether a message is logged or passed on, the maximum priority of messages
will be limited to the specified level - messages with a higher priority
will be set to the specified priority.

Another way to view this is that C<< ->level >> filters out messages with
a too low priority, while C<< ->cap >> modifies messages with a too high
priority.

This is useful when different log targets have different interpretations
of priority. For example, for a specific command line program, a wrong
command line switch might well result in a C<fatal> log message, while the
same message, logged to syslog, is likely I<not> fatal to the system or
syslog facility as a whole, but more likely a mere C<error>.

This can be modeled by having a stderr logger that logs messages "as-is"
and a syslog logger that logs messages with a level cap of, say, C<error>,
or, for truly system-critical components, actually C<critical>.

=cut

sub _lvl_lst {
   map {
      $_ > 0 && $_ <= 9 ? $_+0
      : $_ eq "all"     ? (1 .. 9)
      : $STR2LEVEL{$_} || Carp::croak "$_: not a valid logging level, caught"
   } @_
}

sub _lvl {
   $_[0] =~ /^(?:0|off|none)$/ ? 0 : (_lvl_lst $_[0])[-1]
}

our $NOP_CB = sub { 0 };

sub levels {
   my $ctx = shift;
   $ctx->[1] = 0;
   $ctx->[1] |= 1 << $_
      for &_lvl_lst;
   AnyEvent::Log::_reassess;
}

sub level {
   my $ctx = shift;
   $ctx->[1] = ((1 << &_lvl) - 1) << 1;
   AnyEvent::Log::_reassess;
}

sub enable {
   my $ctx = shift;
   $ctx->[1] |= 1 << $_
      for &_lvl_lst;
   AnyEvent::Log::_reassess;
}

sub disable {
   my $ctx = shift;
   $ctx->[1] &= ~(1 << $_)
      for &_lvl_lst;
   AnyEvent::Log::_reassess;
}

sub cap {
   my $ctx = shift;
   $ctx->[5] = &_lvl;
}

=back

=head3 SLAVE CONTEXTS

The following methods attach and detach another logging context to a
logging context.

Log messages are propagated to all slave contexts, unless the logging
callback consumes the message.

=over 4

=item $ctx->attach ($ctx2[, $ctx3...])

Attaches the given contexts as slaves to this context. It is not an error
to add a context twice (the second add will be ignored).

A context can be specified either as package name or as a context object.

=item $ctx->detach ($ctx2[, $ctx3...])

Removes the given slaves from this context - it's not an error to attempt
to remove a context that hasn't been added.

A context can be specified either as package name or as a context object.

=item $ctx->slaves ($ctx2[, $ctx3...])

Replaces all slaves attached to this context by the ones given.

=cut

sub attach {
   my $ctx = shift;

   $ctx->[2]{$_+0} = $_
      for map { AnyEvent::Log::ctx $_ } @_;
}

sub detach {
   my $ctx = shift;

   delete $ctx->[2]{$_+0}
      for map { AnyEvent::Log::ctx $_ } @_;
}

sub slaves {
   undef $_[0][2];
   &attach;
}

=back

=head3 LOG TARGETS

The following methods configure how the logging context actually does
the logging (which consists of formatting the message and printing it or
whatever it wants to do with it).

=over 4

=item $ctx->log_cb ($cb->($str))

Replaces the logging callback on the context (C<undef> disables the
logging callback).

The logging callback is responsible for handling formatted log messages
(see C<fmt_cb> below) - normally simple text strings that end with a
newline (and are possibly multiline themselves).

It also has to return true iff it has consumed the log message, and false
if it hasn't. Consuming a message means that it will not be sent to any
slave context. When in doubt, return C<0> from your logging callback.

Example: a very simple logging callback, simply dump the message to STDOUT
and do not consume it.

   $ctx->log_cb (sub { print STDERR shift; 0 });

You can filter messages by having a log callback that simply returns C<1>
and does not do anything with the message, but this counts as "message
being logged" and might not be very efficient.

Example: propagate all messages except for log levels "debug" and
"trace". The messages will still be generated, though, which can slow down
your program.

   $ctx->levels ("debug", "trace");
   $ctx->log_cb (sub { 1 }); # do not log, but eat debug and trace messages

=item $ctx->fmt_cb ($fmt_cb->($timestamp, $orig_ctx, $level, $message))

Replaces the formatting callback on the context (C<undef> restores the
default formatter).

The callback is passed the (possibly fractional) timestamp, the original
logging context (object, not title), the (numeric) logging level and
the raw message string and needs to return a formatted log message. In
most cases this will be a string, but it could just as well be an array
reference that just stores the values.

If, for some reason, you want to use C<caller> to find out more about the
logger then you should walk up the call stack until you are no longer
inside the C<AnyEvent::Log> package.

Example: format just the raw message, with numeric log level in angle
brackets.

   $ctx->fmt_cb (sub {
      my ($time, $ctx, $lvl, $msg) = @_;

      "<$lvl>$msg\n"
   });

Example: return an array reference with just the log values, and use
C<PApp::SQL::sql_exec> to store the message in a database.

   $ctx->fmt_cb (sub { \@_ });
   $ctx->log_cb (sub {
      my ($msg) = @_;

      sql_exec "insert into log (when, subsys, prio, msg) values (?, ?, ?, ?)",
               $msg->[0] + 0,
               "$msg->[1]",
               $msg->[2] + 0,
               "$msg->[3]";

      0
   });

=item $ctx->log_to_warn

Sets the C<log_cb> to simply use C<CORE::warn> to report any messages
(usually this logs to STDERR).

=item $ctx->log_to_file ($path)

Sets the C<log_cb> to log to a file (by appending), unbuffered. The
function might return before the log file has been opened or created.

=item $ctx->log_to_path ($path)

Same as C<< ->log_to_file >>, but opens the file for each message. This
is much slower, but allows you to change/move/rename/delete the file at
basically any time.

Needless(?) to say, if you do not want to be bitten by some evil person
calling C<chdir>, the path should be absolute. Doesn't help with
C<chroot>, but hey...

=item $ctx->log_to_syslog ([$facility])

Logs all messages via L<Sys::Syslog>, mapping C<trace> to C<debug> and
all the others in the obvious way. If specified, then the C<$facility> is
used as the facility (C<user>, C<auth>, C<local0> and so on). The default
facility is C<user>.

Note that this function also sets a C<fmt_cb> - the logging part requires
an array reference with [$level, $str] as input.

=cut

sub log_cb {
   my ($ctx, $cb) = @_;

   $ctx->[3] = $cb;
}

sub fmt_cb {
   my ($ctx, $cb) = @_;

   $ctx->[4] = $cb;
}

sub log_to_warn {
   my ($ctx, $path) = @_;

   $ctx->log_cb (sub {
      warn shift;
      0
   });
}

# this function is a good example of why threads are a must,
# simply for priority inversion.
sub _log_to_disk {
   # eval'uating this at runtime saves 220kb rss - perl has become
   # an insane memory waster.
   eval q{ # poor man's autoloading {}
      sub _log_to_disk {
         my ($ctx, $path, $keepopen) = @_;

         my $fh;
         my @queue;
         my $delay;
         my $disable;

         use AnyEvent::IO ();

         my $kick = sub {
            undef $delay;
            return unless @queue;
            $delay = 1;

            # we pass $kick to $kick, so $kick itself doesn't keep a reference to $kick.
            my $kick = shift;

            # write one or more messages
            my $write = sub {
               # we write as many messages as have been queued
               my $data = join "", @queue;
               @queue = ();

               AnyEvent::IO::aio_write $fh, $data, sub {
                  $disable = 1;
                  @_
                     ? ($_[0] == length $data or AE::log 4 => "unable to write to logfile '$path': short write")
                     :                           AE::log 4 => "unable to write to logfile '$path': $!";
                  undef $disable;

                  if ($keepopen) {
                     $kick->($kick);
                  } else {
                     AnyEvent::IO::aio_close ($fh, sub {
                        undef $fh;
                        $kick->($kick);
                     });
                  }
               };
            };

            if ($fh) {
               $write->();
            } else {
               AnyEvent::IO::aio_open
                  $path,
                  AnyEvent::IO::O_CREAT | AnyEvent::IO::O_WRONLY | AnyEvent::IO::O_APPEND,
                  0666,
                  sub {
                     $fh = shift
                        or do {
                           $disable = 1;
                           AE::log 4 => "unable to open logfile '$path': $!";
                           undef $disable;
                           return;
                        };

                     $write->();
                  }
               ;
            }
         };

         $ctx->log_cb (sub {
            return if $disable;
            push @queue, shift;
            $kick->($kick) unless $delay;
            0
         });

         $kick->($kick) if $keepopen; # initial open
      };
   };
   die if $@;
   &_log_to_disk
}

sub log_to_file {
   my ($ctx, $path) = @_;

   _log_to_disk $ctx, $path, 1;
}

sub log_to_path {
   my ($ctx, $path) = @_;

   _log_to_disk $ctx, $path, 0;
}

sub log_to_syslog {
   my ($ctx, $facility) = @_;

   require Sys::Syslog;

   $ctx->fmt_cb (sub {
      my $str = $_[3];
      $str =~ s/\n(?=.)/\n+ /g;

      [$_[2], "($_[1][0]) $str"]
   });

   $facility ||= "user";

   $ctx->log_cb (sub {
      my $lvl = $_[0][0] < 9 ? $_[0][0] : 8;

      Sys::Syslog::syslog ("$facility|" . ($lvl - 1), $_)
         for split /\n/, $_[0][1];

      0
   });
}

=back

=head3 MESSAGE LOGGING

These methods allow you to log messages directly to a context, without
going via your package context.

=over 4

=item $ctx->log ($level, $msg[, @params])

Same as C<AnyEvent::Log::log>, but uses the given context as log context.

Example: log a message in the context of another package.

   (AnyEvent::Log::ctx "Other::Package")->log (warn => "heely bo");

=item $logger = $ctx->logger ($level[, \$enabled])

Same as C<AnyEvent::Log::logger>, but uses the given context as log
context.

=cut

*log    = \&AnyEvent::Log::_log;
*logger = \&AnyEvent::Log::_logger;

=back

=cut

package AnyEvent::Log;

=head1 CONFIGURATION VIA $ENV{PERL_ANYEVENT_LOG}

Logging can also be configured by setting the environment variable
C<PERL_ANYEVENT_LOG> (or C<AE_LOG>).

The value consists of one or more logging context specifications separated
by C<:> or whitespace. Each logging specification in turn starts with a
context name, followed by C<=>, followed by zero or more comma-separated
configuration directives, here are some examples:

   # set default logging level
   filter=warn

   # log to file instead of to stderr
   log=file=/tmp/mylog

   # log to file in addition to stderr
   log=+%file:%file=file=/tmp/mylog

   # enable debug log messages, log warnings and above to syslog
   filter=debug:log=+%warnings:%warnings=warn,syslog=LOG_LOCAL0

   # log trace messages (only) from AnyEvent::Debug to file
   AnyEvent::Debug=+%trace:%trace=only,trace,file=/tmp/tracelog

A context name in the log specification can be any of the following:

=over 4

=item C<collect>, C<filter>, C<log>

Correspond to the three predefined C<$AnyEvent::Log::COLLECT>,
C<AnyEvent::Log::FILTER> and C<$AnyEvent::Log::LOG> contexts.

=item C<%name>

Context names starting with a C<%> are anonymous contexts created when the
name is first mentioned. The difference to package contexts is that by
default they have no attached slaves.

=item a perl package name

Any other string references the logging context associated with the given
Perl C<package>. In the unlikely case where you want to specify a package
context that matches on of the other context name forms, you can add a
C<::> to the package name to force interpretation as a package.

=back

The configuration specifications can be any number of the following:

=over 4

=item C<stderr>

Configures the context to use Perl's C<warn> function (which typically
logs to C<STDERR>). Works like C<log_to_warn>.

=item C<file=>I<path>

Configures the context to log to a file with the given path. Works like
C<log_to_file>.

=item C<path=>I<path>

Configures the context to log to a file with the given path. Works like
C<log_to_path>.

=item C<syslog> or C<syslog=>I<expr>

Configures the context to log to syslog. If I<expr> is given, then it is
evaluated in the L<Sys::Syslog> package, so you could use:

   log=syslog=LOG_LOCAL0

=item C<nolog>

Configures the context to not log anything by itself, which is the
default. Same as C<< $ctx->log_cb (undef) >>.

=item C<cap=>I<level>

Caps logging messages entering this context at the given level, i.e.
reduces the priority of messages with higher priority than this level. The
default is C<0> (or C<off>), meaning the priority will not be touched.

=item C<0> or C<off>

Sets the logging level of the context to C<0>, i.e. all messages will be
filtered out.

=item C<all>

Enables all logging levels, i.e. filtering will effectively be switched
off (the default).

=item C<only>

Disables all logging levels, and changes the interpretation of following
level specifications to enable the specified level only.

Example: only enable debug messages for a context.

   context=only,debug

=item C<except>

Enables all logging levels, and changes the interpretation of following
level specifications to disable that level. Rarely used.

Example: enable all logging levels except fatal and trace (this is rather
nonsensical).

   filter=exept,fatal,trace

=item C<level>

Enables all logging levels, and changes the interpretation of following
level specifications to be "that level or any higher priority
message". This is the default.

Example: log anything at or above warn level.

   filter=warn

   # or, more verbose
   filter=only,level,warn

=item C<1>..C<9> or a logging level name (C<error>, C<debug> etc.)

A numeric loglevel or the name of a loglevel will be interpreted according
to the most recent C<only>, C<except> or C<level> directive. By default,
specifying a logging level enables that and any higher priority messages.

=item C<+>I<context>

Attaches the named context as slave to the context.

=item C<+>

A lone C<+> detaches all contexts, i.e. clears the slave list from the
context. Anonymous (C<%name>) contexts have no attached slaves by default,
but package contexts have the parent context as slave by default.

Example: log messages from My::Module to a file, do not send them to the
default log collector.

   My::Module=+,file=/tmp/mymodulelog

=back

Any character can be escaped by prefixing it with a C<\> (backslash), as
usual, so to log to a file containing a comma, colon, backslash and some
spaces in the filename, you would do this:

   PERL_ANYEVENT_LOG='log=file=/some\ \:file\ with\,\ \\-escapes'

Since whitespace (which includes newlines) is allowed, it is fine to
specify multiple lines in C<PERL_ANYEVENT_LOG>, e.g.:

   PERL_ANYEVENT_LOG="
      filter=warn
      AnyEvent::Debug=+%trace
      %trace=only,trace,+log
   " myprog

Also, in the unlikely case when you want to concatenate specifications,
use whitespace as separator, as C<::> will be interpreted as part of a
module name, an empty spec with two separators:

   PERL_ANYEVENT_LOG="$PERL_ANYEVENT_LOG MyMod=debug"

=cut

for (my $spec = $ENV{PERL_ANYEVENT_LOG}) {
   my %anon;

   my $pkg = sub {
      $_[0] eq "log"              ? $LOG
      : $_[0] eq "filter"         ? $FILTER
      : $_[0] eq "collect"        ? $COLLECT
      : $_[0] =~ /^%(.+)$/        ? ($anon{$1} ||= do { my $ctx = ctx undef; $ctx->[0] = $_[0]; $ctx })
      : $_[0] =~ /^(.*?)(?:::)?$/ ? ctx "$1" # egad :/
      : die # never reached?
   };

   /\G[[:space:]]+/gc; # skip initial whitespace

   while (/\G((?:[^:=[:space:]]+|::|\\.)+)=/gc) {
      my $ctx = $pkg->($1);
      my $level = "level";

      while (/\G((?:[^,:[:space:]]+|::|\\.)+)/gc) {
         for ("$1") {
            if ($_ eq "stderr"               ) { $ctx->log_to_warn;
            } elsif (/^file=(.+)/            ) { $ctx->log_to_file ("$1");
            } elsif (/^path=(.+)/            ) { $ctx->log_to_path ("$1");
            } elsif (/^syslog(?:=(.*))?/     ) { require Sys::Syslog; $ctx->log_to_syslog ("$1");
            } elsif ($_ eq "nolog"           ) { $ctx->log_cb (undef);
            } elsif (/^cap=(.+)/             ) { $ctx->cap ("$1");
            } elsif (/^\+(.+)$/              ) { $ctx->attach ($pkg->("$1"));
            } elsif ($_ eq "+"               ) { $ctx->slaves;
            } elsif ($_ eq "off" or $_ eq "0") { $ctx->level (0);
            } elsif ($_ eq "all"             ) { $ctx->level ("all");
            } elsif ($_ eq "level"           ) { $ctx->level ("all"); $level = "level";
            } elsif ($_ eq "only"            ) { $ctx->level ("off"); $level = "enable";
            } elsif ($_ eq "except"          ) { $ctx->level ("all"); $level = "disable";
            } elsif (/^\d$/                  ) { $ctx->$level ($_);
            } elsif (exists $STR2LEVEL{$_}   ) { $ctx->$level ($_);
            } else                             { die "PERL_ANYEVENT_LOG ($spec): parse error at '$_'\n";
            }
         }

         /\G,/gc or last;
      }

      /\G[:[:space:]]+/gc or last;
   }

   /\G[[:space:]]+/gc; # skip trailing whitespace

   if (/\G(.+)/g) {
      die "PERL_ANYEVENT_LOG ($spec): parse error at '$1'\n";
   }
}

=head1 EXAMPLES

This section shows some common configurations, both as code, and as
C<PERL_ANYEVENT_LOG> string.

=over 4

=item Setting the global logging level.

Either put C<PERL_ANYEVENT_VERBOSE=><number> into your environment before
running your program, use C<PERL_ANYEVENT_LOG> or modify the log level of
the root context at runtime:

   PERL_ANYEVENT_VERBOSE=5 ./myprog

   PERL_ANYEVENT_LOG=log=warn

   $AnyEvent::Log::FILTER->level ("warn");

=item Append all messages to a file instead of sending them to STDERR.

This is affected by the global logging level.

   $AnyEvent::Log::LOG->log_to_file ($path);

   PERL_ANYEVENT_LOG=log=file=/some/path

=item Write all messages with priority C<error> and higher to a file.

This writes them only when the global logging level allows it, because
it is attached to the default context which is invoked I<after> global
filtering.

   $AnyEvent::Log::FILTER->attach (
      new AnyEvent::Log::Ctx log_to_file => $path);

   PERL_ANYEVENT_LOG=filter=+%filelogger:%filelogger=file=/some/path

This writes them regardless of the global logging level, because it is
attached to the toplevel context, which receives all messages I<before>
the global filtering.

   $AnyEvent::Log::COLLECT->attach (
      new AnyEvent::Log::Ctx log_to_file => $path);

   PERL_ANYEVENT_LOG=%filelogger=file=/some/path:collect=+%filelogger

In both cases, messages are still written to STDERR.

=item Additionally log all messages with C<warn> and higher priority to
C<syslog>, but cap at C<error>.

This logs all messages to the default log target, but also logs messages
with priority C<warn> or higher (and not filtered otherwise) to syslog
facility C<user>. Messages with priority higher than C<error> will be
logged with level C<error>.

   $AnyEvent::Log::LOG->attach (
      new AnyEvent::Log::Ctx
         level  => "warn",
         cap    => "error",
         syslog => "user",
   );

   PERL_ANYEVENT_LOG=log=+%syslog:%syslog=warn,cap=error,syslog

=item Write trace messages (only) from L<AnyEvent::Debug> to the default logging target(s).

Attach the C<$AnyEvent::Log::LOG> context to the C<AnyEvent::Debug>
context - this simply circumvents the global filtering for trace messages.

   my $debug = AnyEvent::Debug->AnyEvent::Log::ctx;
   $debug->attach ($AnyEvent::Log::LOG);

   PERL_ANYEVENT_LOG=AnyEvent::Debug=+log

This of course works for any package, not just L<AnyEvent::Debug>, but
assumes the log level for AnyEvent::Debug hasn't been changed from the
default.

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://anyevent.schmorp.de

=cut

1

