package Object::Event;
use common::sense;
use Carp qw/croak/;
use AnyEvent::Util qw/guard/;

use sort 'stable';

our $DEBUG = $ENV{PERL_OBJECT_EVENT_DEBUG};

=head1 NAME

Object::Event - A class that provides an event callback interface

=head1 VERSION

Version 1.23

=cut

our $VERSION = '1.23';

=head1 SYNOPSIS

   package foo;
   use Object::Event;

   our @ISA = qw/Object::Event/;

   package main;
   my $o = foo->new;

   my $regguard = $o->reg_cb (foo => sub {
      print "I got an event, with these args: $_[1], $_[2], $_[3]\n";
   });

   $o->event (foo => 1, 2, 3);

   $o->unreg_cb ($regguard);
   # or just:
   $regguard = undef;


=head1 DESCRIPTION

This module was mainly written for L<AnyEvent::XMPP>, L<AnyEvent::IRC>,
L<AnyEvent::HTTPD> and L<BK> to provide a consistent API for registering and
emitting events.  Even though I originally wrote it for those modules I released
it separately in case anyone may find this module useful.

For more comprehensive event handling see also L<Glib> and L<POE>.

This class provides a simple way to extend a class, by inheriting from
this class, with an event callback interface.

You will be able to register callbacks for events, identified by their names (a
string) and call them later by invoking the C<event> method with the event name
and some arguments. 

There is even a syntactic sugar which allows to call methods on the instances
of L<Object::Event>-derived classes, to invoke events.  For this feature see
the L<EVENT METHODS> section of this document.

=head1 PERFORMANCE

In the first version as presented here no special performance optimisations
have been applied. So take care that it is fast enough for your purposes.  At
least for modules like L<AnyEvent::XMPP> the overhead is probably not
noticeable, as other technologies like XML already waste a lot more CPU cycles.
Also I/O usually introduces _much_ larger/longer overheads than this simple
event interface.

=head1 FUNCTIONS

=over 4

=item Object::Event::register_priority_alias ($alias, $priority)

This package function will add a global priority alias.
If C<$priority> is undef the alias will be removed.

There are 4 predefined aliases:

   before     =>  1000
   ext_before =>   500
   ext_after  =>  -500
   after      => -1000

See also the C<reg_cb> method for more information about aliases.

=cut

our %PRIO_MAP = (
   before     =>  1000,
   ext_before =>   500,
   ext_after  =>  -500,
   after      => -1000
);

sub register_priority_alias {
   my ($alias, $prio) = @_;
   $PRIO_MAP{$alias} = $prio;

   unless (defined $PRIO_MAP{$alias}) {
      delete $PRIO_MAP{$alias} 
   }
}

=back

=head1 METHODS

=over 4

=item Object::Event->new (%args)

=item Your::Subclass::Of::Object::Event->new (%args)

This is the constructor for L<Object::Event>,
it will create a blessed hash reference initialized with C<%args>.

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

=item $obj->init_object_events ()

This method should only be called if you are not able to call the C<new>
constructor of this class. Then you need to call this method to initialize
the event system.

=cut

sub init_object_events {
   my ($self) = @_;

   my $pkg = ref $self;

   _init_methods ($pkg) unless *{"$pkg\::__OE_METHODS"}{HASH};

   $self->{__oe_cb_gen} = "a"; # generation counter

   $self->{__oe_events} = {
      map {
         ($_ => [@{${"$pkg\::__OE_METHODS"}{$_}}])
      } keys %{"$pkg\::__OE_METHODS"}
   };
}

=item $obj->set_exception_cb ($cb->($exception, $eventname))

This method installs a callback that will be called when some other
event callback threw an exception. The first argument to C<$cb>
will be the exception and the second the event name.

=cut

sub set_exception_cb {
   my ($self, $cb) = @_;
   $self->{__oe_exception_cb} = $cb;
}

=item $guard = $obj->reg_cb ($eventname => $cb->($obj, @args), ...)

=item $guard = $obj->reg_cb ($eventname => $prio, $cb->($obj, @args), ...)

This method registers a callback C<$cb1> for the event with the
name C<$eventname1>. You can also pass multiple of these eventname => callback
pairs.

The return value C<$guard> will be a guard that represents the set of callbacks
you have installed. You can either just "forget" the contents of C<$guard> to
unregister the callbacks or call C<unreg_cb> with that ID to remove those
callbacks again. If C<reg_cb> is called in a void context no guard is returned
and you have no chance to unregister the registered callbacks.

The first argument for callbacks registered with the C<reg_cb> function will
always be the master object C<$obj>.

The return value of the callbacks are ignored. If you need to pass
any information from a handler to the caller of the event you have to
establish your own "protocol" to do this. I recommend to pass an array
reference to the handlers:

   $obj->reg_cb (event_foobar => sub {
      my ($self, $results) = @_;
      push @$results, time / 30;
   });

   my @results;
   $obj->event (event_foobar => \@results);
   for (@results) {
      # ...
   }

The order of the callbacks in the call chain of the event depends on their
priority. If you didn't specify any priority (see below) they get the default
priority of 0, and are appended to the other priority 0 callbacks.
The higher the priority number, the earlier the callbacks gets called in the chain.

If C<$eventname1> starts with C<'before_'> the callback gets a priority
of 1000, and if it starts with C<'ext_before_'> it gets the priority 500.
C<'after_'> is mapped to the priority -1000 and C<'ext_after_'> to -500.

If you want more fine grained control you can pass an array reference
instead of the event name:

   ($eventname1, $prio) = ('test_abc', 100);
   $obj->reg_cb ([$eventname1, $prio] => sub {
      ...
   });

=cut

our @DEBUG_STACK;

sub _debug_cb {
   my ($callback) = @_;

   sub {
      my @a = @_;
      my $dbcb = $_[0]->{__oe_cbs}->[0]->[0];
      my $nam  = $_[0]->{__oe_cbs}->[2];
      push @DEBUG_STACK, $dbcb;

      my $pad = "  " x scalar @DEBUG_STACK;

      printf "%s-> %s\n", $pad, $dbcb->[3];

      eval { $callback->(@a) };
      my $e = $@;

      printf "%s<- %s\n", $pad, $dbcb->[3];

      pop @DEBUG_STACK;

      die $e if $e;
      ()
   };

}
sub _print_event_debug {
   my ($ev) = @_;
   my $pad = "  " x scalar @DEBUG_STACK;
   my ($pkg, $file, $line) = caller (1);
   for my $path (@INC) {
      last if $file =~ s/^\Q$path\E\/?//;
   }
   printf "%s!! %s @ %s:%d (%s::)\n", $pad, $ev, $file, $line, $pkg
}

sub _register_event_struct {
   my ($self, $event, $prio, $gen, $callback, $debug) = @_;

   my $reg = ($self->{__oe_events} ||= {});
   my $idx = 0;
   $reg->{$event} ||= [];
   my $evlist = $reg->{$event};

   for my $ev (@$evlist) {
      last if $ev->[0] < $prio;
      $idx++;
   }

   my $cb = $callback;
   $cb = _debug_cb ($callback) if $DEBUG > 1;

   splice @$evlist, $idx, 0, [$prio, "$callback|$gen", undef, $debug, $cb];
}

sub reg_cb {
   my ($self, @args) = @_;

   my $debuginfo = caller;
   if ($DEBUG > 0) {
      my ($pkg,$file,$line) = caller;
      for my $path (@INC) {
         last if $file =~ s/^\Q$path\E\/?//;
      }
      $debuginfo = sprintf "%s:%d (%s::)", $file, $line, $pkg;
   }

   my $gen = $self->{__oe_cb_gen}++; # get gen counter

   my @cbs;
   while (@args) {
      my ($ev, $sec) = (shift @args, shift @args);

      my ($prio, $cb) = (0, undef);

      if (ref $sec) {
         for my $prefix (keys %PRIO_MAP) {
            if ($ev =~ s/^(\Q$prefix\E)_//) {
               $prio = $PRIO_MAP{$prefix};
               last;
            }
         }

         $cb = $sec;

      } else {
         $prio = $sec;
         $cb   = shift @args;
      }

      $self->_register_event_struct ($ev, $prio, $gen, $cb, $debuginfo);
      push @cbs, $cb;
   }

   defined wantarray
      ? \(my $g = guard { if ($self) { $self->unreg_cb ($_, $gen) for @cbs } })
      : ()
}

=item $obj->unreg_cb ($cb)

Removes the callback C<$cb> from the set of registered callbacks.

=cut

sub unreg_cb {
   my ($self, $cb, $gen) = @_;

   if (ref ($cb) eq 'REF') {
      # we've got a guard object
      $$cb = undef;
      return;
   }

   return unless defined $cb; # some small safety against bad arguments

   my $evs = $self->{__oe_events};

   # $gen is neccessary for the times where we use the guard to remove
   # something, because we only have the callback as ID we need to track the
   # generation of the registration for these:
   #
   # my $cb = sub { ... };
   # my $g = $o->reg_cb (a => $cb);
   # $g = $o->reg_cb (a => $cb);
   my ($key, $key_len) = defined $gen
                            ? ("$cb|$gen", length "$cb|$gen")
                            : ("$cb", length "$cb");
   for my $reg (values %$evs) {
      @$reg = grep { (substr $_->[1], 0, $key_len) ne $key } @$reg;
   }
}

=item my $handled = $obj->event ($eventname, @args)

Emits the event C<$eventname> and passes the arguments C<@args> to the
callbacks. The return value C<$handled> is a true value in case some handler
was found and run. It returns false if no handler was found (see also the
C<handles> method below). Basically: It returns the same value as the
C<handles> method.

Please note that an event can be stopped and reinvoked while it is being
handled.

See also the specification of the before and after events in C<reg_cb> above.

NOTE: Whenever an event is emitted the current set of callbacks registered
to that event will be used. So, if you register another event callback for the
same event that is executed at the moment, it will be called the B<next> time 
when the event is emitted. Example:

   $obj->reg_cb (event_test => sub {
      my ($obj) = @_;

      print "Test1\n";
      $obj->unreg_me;

      $obj->reg_cb (event_test => sub {
         my ($obj) = @_;
         print "Test2\n";
         $obj->unreg_me;
      });
   });

   $obj->event ('event_test'); # prints "Test1"
   $obj->event ('event_test'); # prints "Test2"

=cut

sub event {
   my ($self, $ev, @arg) = @_;

   my @cbs;

   if (ref ($ev) eq 'ARRAY') {
      @cbs = @$ev;

   } else {
      my $evs = $self->{__oe_events}->{$ev} || [];
      @cbs = @$evs;
   }

   ######################
   # Legacy code start
   ######################
   if ($self->{__oe_forwards}) {
      # we are inserting a forward callback into the callchain.
      # first search the start of the 0 priorities...
      my $idx = 0;
      for my $ev (@cbs) {
         last if $ev->[0] <= 0;
         $idx++;
      }

      # then splice in the stuff
      my $cb = sub {
         for my $fw (keys %{$self->{__oe_forwards}}) {
            my $f = $self->{__oe_forwards}->{$fw};
            local $f->[0]->{__oe_forward_stop} = 0;
            eval {
               $f->[1]->($self, $f->[0], $ev, @arg);
            };
            if ($@) {
               if ($self->{__oe_exception_cb}) {
                  $self->{__oe_exception_cb}->($@, $ev);
               } else {
                  warn "unhandled callback exception on forward event "
                       . "($ev, $self, $f->[0], @arg): $@\n";
               }
            } elsif ($f->[0]->{__oe_forward_stop}) {
               $self->stop_event;
            }
         }
      };

      splice @cbs, $idx, 0, [0, "$cb", undef, undef, $cb];
   }
   ######################
   # Legacy code end
   ######################

   _print_event_debug ($ev) if $DEBUG > 1;

   return unless @cbs;

   local $self->{__oe_cbs} = [\@cbs, \@arg, $ev];
   eval {
      $cbs[0]->[4]->($self, @arg), shift @cbs while @cbs;
      ()
   };
   if ($@) {
      if (not ($self->{__oe_exception_rec})
          && $self->{__oe_exception_cb}) {
         local $self->{__oe_exception_rec} = [$ev, $self, @arg];
         $self->{__oe_exception_cb}->($@, $ev);

      } elsif ($self->{__oe_exception_rec}) {
         warn "recursion through exception callback "
              . "(@{$self->{__oe_exception_rec}}) => "
              . "($ev, $self, @arg): $@\n";
      } else {
         warn "unhandled callback exception on event ($ev, $self, @arg): $@\n";
      }
   }

   1 # handlers ran
}

=item my $bool = $obj->handles ($eventname)

This method returns true if any event handler has been setup for
the event C<$eventname>.

It returns false if that is not the case.

=cut

sub handles {
   my ($self, $ev) = @_;

   exists $self->{__oe_events}->{$ev}
      && @{$self->{__oe_events}->{$ev}} > 0
}

=item $obj->event_name

Returns the name of the currently executed event.

=cut

sub event_name {
   my ($self) = @_;
   return unless $self->{__oe_cbs};
   $self->{__oe_cbs}->[2]
}

=item $obj->unreg_me

Unregisters the currently executed callback.

=cut

sub unreg_me {
   my ($self) = @_;
   return unless $self->{__oe_cbs} && @{$self->{__oe_cbs}->[0]};
   $self->unreg_cb ($self->{__oe_cbs}->[0]->[0]->[1])
}

=item $continue_cb = $obj->stop_event

This method stops the execution of callbacks of the current
event, and returns (in non-void context) a callback that will
let you continue the execution.

=cut

sub stop_event {
   my ($self) = @_;

   return unless $self->{__oe_cbs} && @{$self->{__oe_cbs}->[0]};

   my $r;

   if (defined wantarray) {
      my @ev = ([@{$self->{__oe_cbs}->[0]}], @{$self->{__oe_cbs}->[1]});
      shift @{$ev[0]}; # shift away current cb
      $r = sub { $self->event (@ev) }
   }

   # XXX: Old legacy code for forwards!
   $self->{__oe_forward_stop} = 1;

   @{$self->{__oe_cbs}->[0]} = ();

   $r
}

=item $obj->add_forward ($obj, $cb)

B<DEPRECATED: Don't use it!> Just for backward compatibility for L<AnyEvent::XMPP>
version 0.4.

=cut

sub add_forward {
   my ($self, $obj, $cb) = @_;
   $self->{__oe_forwards}->{$obj} = [$obj, $cb];
}

=item $obj->remove_forward ($obj)

B<DEPRECATED: Don't use it!> Just for backward compatibility for L<AnyEvent::XMPP>
version 0.4.

=cut

sub remove_forward {
   my ($self, $obj) = @_;
   delete $self->{__oe_forwards}->{$obj};
   if (scalar (keys %{$self->{__oe_forwards}}) <= 0) {
      delete $self->{__oe_forwards};
   }
}

sub _event {
   my $self = shift;
   $self->event (@_)
}

=item $obj->remove_all_callbacks ()

This method removes all registered event callbacks from this object.

=cut

sub remove_all_callbacks {
   my ($self) = @_;
   $self->{__oe_events} = {};
   delete $self->{__oe_exception_cb};
}

=item $obj->events_as_string_dump ()

This method returns a string dump of all registered event callbacks.
This method is only for debugging purposes.

=cut

sub events_as_string_dump {
   my ($self) = @_;
   my $str = '';
   for my $ev (keys %{$self->{__oe_events}}) {
      my $evr = $self->{__oe_events}->{$ev};
      $str .=
         "$ev:\n"
         . join ('', map { sprintf "   %5d %s\n", $_->[0], $_->[3] } @$evr)
         . "\n";
   }
   $str
}

=back

=head1 EVENT METHODS

You can define static methods in a package that act as event handler.
This is done by using Perl's L<attributes> functionality. To make
a method act as event handler you need to add the C<event_cb> attribute
to it.

B<NOTE:> Please note that for this to work the methods need to be defined at
compile time. This means that you are not able to add event handles using
C<AUTOLOAD>!

B<NOTE:> Perl's attributes have a very basic syntax, you have to take
care to not insert any whitespace, the attribute must be a single
string that contains no whitespace. That means: C<event_cb (1)> is not the
same as C<event_cb(1)>!

Here is an example:

   package foo;
   use base qw/Object::Event/;

   sub test : event_cb { print "test event handler!\n" }

   package main;
   my $o = foo->new;
   $o->test ();        # prints 'test event handler!'
   $o->event ('test'); # also prints 'test event handler!'!

In case you want to set a priority use this syntax:

   sub test : event_cb(-1000) { ... }

Or:

   sub test : event_cb(after) { ... }

You may want to have a look at the tests of the L<Object::Event>
distribution for more examples.

=head2 ALIASES

If you want to define multiple event handlers as package method
you can use the C<event_cb> attribute with an additional argument:

   package foo;
   use base qw/Object::Event/;

   sub test : event_cb { # default prio is always 0
      print "middle\n";
   }

   sub test_last : event_cb(-1,test) {
      print "after\n";
   }

   sub test_first : event_cb(1,test) {
      print "before\n";
   }

   package main;
   my $o = foo->new;
   $o->test ();        # prints "after\n" "middle\n" "before\n"
   $o->event ('test'); # prints the same
   $o->test_first ();  # also prints the same

B<NOTE:> Please note that if you don't provide any order the methods
are sorted I<alphabetically>:

   package foo;
   use base qw/Object::Event/;

   sub test : event_cb { # default prio is always 0
      print "middle\n";
   }

   sub x : event_cb(, test) { # please note the empty element before the ','! 
      print "after\n";
   }

   sub a : event_cb(, test) {
      print "before\n";
   }

   package main;
   my $o = foo->new;
   $o->test ();        # prints "after\n" "middle\n" "before\n"
   $o->event ('test'); # prints the same
   $o->x ();           # also prints the same

=head2 ALIAS ORDERING

The ordering of how the methods event handlers are called if they
are all defined for the same event is strictly defined:

=over 4

=item 1.

Ordering of the methods for the same event in the inheritance hierarchy
is always dominated by the priority of the event callback.

=item 2.

Then if there are multiple methods with the same priority the place in the
inheritance hierarchy defines in which order the methods are executed. The
higher up in the hierarchy the class is, the earlier it will be called.

=item 3.

Inside a class the name of the method for the event decides which event is
executed first. (All if the priorities are the same)

=back

=cut

our %ATTRIBUTES;

sub FETCH_CODE_ATTRIBUTES {
   my ($pkg, $ref) = @_;
   return () unless exists $ATTRIBUTES{$pkg};
   return () unless exists $ATTRIBUTES{$pkg}->{"$ref"};

   my $a = $ATTRIBUTES{$pkg}->{"$ref"};

   'event_cb' . (
       ($a->[0] ne '' || defined ($b->[1]))
          ? "($a->[0],$b->[1])"
          : ''
    )
}

sub MODIFY_CODE_ATTRIBUTES {
   my ($pkg, $ref, @attrs) = @_;
   grep {
     my $unhandled = 1;

     if ($_ =~ /^event_cb (?:
                   \(
                       \s* ([^\),]*) \s*
                       (?: , \s* ([^\)]+) \s* )?
                   \)
               )?$/x) {
        $ATTRIBUTES{$pkg}->{"$ref"} = [$1, $2];
        $unhandled = 0;
     }

     $unhandled
   } @attrs;
}

sub _init_methods {
   my ($pkg) = @_;

   my $pkg_meth = \%{"$pkg\::__OE_METHODS"};

   for my $superpkg (@{"$pkg\::ISA"}) { # go recursively into super classes
       next unless $superpkg->isa ("Object::Event"); # skip non O::E

       # go into the class if we have not already been there
       _init_methods ($superpkg)
          unless *{"$superpkg\::__OE_METHODS"}{HASH};

       # add the methods of the $superpkg to our own
       for (keys %{"$superpkg\::__OE_METHODS"}) {
          push @{$pkg_meth->{$_}}, @{${"$superpkg\::__OE_METHODS"}{$_} || []};
       }
   }

   my %mymethds;

   # now check each package symbol
   for my $realmeth (keys %{"$pkg\::"}) {

      my $coderef = *{"$pkg\::$realmeth"}{CODE};
      next unless exists $ATTRIBUTES{$pkg}->{"$coderef"}; # skip unattributed methods
      my $m = $ATTRIBUTES{$pkg}->{"$coderef"}; # $m = [$prio, $event_name]

      my $meth = $realmeth;

      if (defined $m->[1]) { # assign alias
         $meth = $m->[1];
      }

      my $cb = $coderef;
      $cb = _debug_cb ($coderef) if $DEBUG > 1;

      push @{$mymethds{$meth}}, [
         (exists $PRIO_MAP{$m->[0]} # set priority
            ? $PRIO_MAP{$m->[0]}
            : 0+$m->[0]),
         "$coderef", # callback id
         $realmeth,  # original method name
         $pkg . '::' . $realmeth, # debug info
         $cb         # the callback

         # only replace if defined, otherwise declarations without definitions will
         # replace the $cb/$coderef with something that calls itself recursively.

      ] if defined &{"$pkg\::$realmeth"};

      #d# warn "REPLACED $pkg $meth (by $realmeth) => $coderef ($m->[1])\n";

      _replace_method ($pkg, $realmeth, $meth);
   }

   # sort my methods by name
   for my $ev (keys %mymethds) {
      @{$mymethds{$ev}} =
         sort { $a->[2] cmp $b->[2] }
            @{$mymethds{$ev}};
   }

   # add my methods to the super class method list
   push @{$pkg_meth->{$_}}, @{$mymethds{$_}}
      for keys %mymethds;

   # sort by priority over all, stable to not confuse names
   for my $ev (keys %$pkg_meth) {
      @{$pkg_meth->{$ev}} =
         sort { $b->[0] <=> $a->[0] }
            @{$pkg_meth->{$ev}};
   }
}

sub _replace_method {
   my ($pkg, $meth, $ev) = @_;

   *{"$pkg\::$meth"} = sub {
      my ($self, @arg) = @_;

      _print_event_debug ($ev) if $DEBUG > 1;

      # either execute callbacks of the object or
      # alternatively (if non present) the inherited ones
      my @cbs = @{
          $self->{__oe_events}->{$ev}
          || ${"$pkg\::__OE_METHODS"}{$ev}
          || []};

      # inline the code of the C<event> method.
      local $self->{__oe_cbs} = [\@cbs, \@arg, $ev];
      eval {
         $cbs[0]->[4]->($self, @arg), shift @cbs while @cbs;
         ()
      };

      if ($@) {
         if (not ($self->{__oe_exception_rec})
             && $self->{__oe_exception_cb}) {

            local $self->{__oe_exception_rec} = [$ev, $self, @arg];
            $self->{__oe_exception_cb}->($@, $ev);

         } elsif ($self->{__oe_exception_rec}) {
            warn "recursion through exception callback "
                 . "(@{$self->{__oe_exception_rec}}) => "
                 . "($ev, $self, @arg): $@\n";

         } else {
            warn "unhandled callback exception on event "
                 . "($ev, $self, @arg): $@\n";
         }
      }

      @cbs > 0
   };
}

=head1 DEBUGGING

There exists a package global variable called C<$DEBUG> that control debugging
capabilities.

Set it to 1 to produce a slightly extended C<events_as_string_dump> output.

Set it to 2 and all events will be dumped in a tree of event invocations.

You can set the variable either in your main program:

   $Object::Event::DEBUG = 2;

Or use the environment variable C<PERL_OBJECT_EVENT_DEBUG>:

   export PERL_OBJECT_EVENT_DEBUG=2

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Object::Event

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Object-Event>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Object-Event>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Object-Event>

=item * Search CPAN

L<http://search.cpan.org/dist/Object-Event>

=back

=head1 ACKNOWLEDGEMENTS

Thanks go to:

  - Mons Anderson for suggesting the 'handles' method and
    the return value of the 'event' method and reporting bugs.

=head1 COPYRIGHT & LICENSE

Copyright 2009-2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
