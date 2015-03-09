package Linux::Input::Joystick;

use base 'Linux::Input';
use strict;
use warnings;

# class data
Linux::Input::Joystick->event_bytes(8);

# return all pending events
sub poll {
  my $self     = shift;
  my $timeout  = shift || ref($self)->timeout();
  my $selector = $self->selector();
  my @ev;
  while (my ($fh) = $selector->can_read($timeout)) {
    my $buffer;
    my $len = sysread($fh, $buffer, Linux::Input::Joystick->event_bytes);
    my ($time, $value, $type, $number) =
      unpack('LsCC', $buffer);
    my $event = {
      time    => $time,
      type    => $type,
      number  => $number,
      value   => $value,
    };
    push @ev, $event;
  }
  return @ev;
}

1;

__END__

=head1 NAME

Linux::Input::Joystick - joystick-specific interface for Linux 2.2+

=head1 SYNOPSIS

Usage

  use YAML;
  my $js = Linux::Input::Joystick->new('/dev/input/js0');
  while (1) {
    my @event = $js->poll(0.01);
    print Dump($_) foreach (@event);
  }

=head1 DESCRIPTION

This is a subclass of L<Linux::Input> that implements the joystick event
interface that versions of Linux from 2.2 onward support.  It differs from
the normal event interface in that it uses a slightly different C struct
to return event information.

This subclass inherits all of L<Linux::Input>'s methods, but differs from
it in the following ways:

=head2 Class Methods

=head3 new

This method takes a C<$filename> and returns a L<Linux::Input::Joystick>
object on success.

B<Example>:

  my $js = Linux::Input::Joystick->new('/dev/input/js1');

=head3 event_bytes

This method returns the size of the joystick event structure (which is always 8)
no matter what platform you run this on.

=head2 Object Methods

=head3 poll

This method takes a C<$timeout> as a parameter and returns an list of
C<@events> after that timeout has elapsed.  The hashrefs inside C<@events>
have the following key/value pairs.

=over 2

=item time

This is the time in microseconds that this event happened.

=item type

This is the type of event.

=item number

This number represents a more specific instance of type.
For example, if type is 1 (meaning button event), then
number might be 5 (meaning button 5 moved).

=item value

This number specifies what happened.   Keeping the previous
example in mind, if the value received is 1, that means
the button was pressed.  However, if it's 0, that means
the button was released.

=back

For more information on what values to expect in this hashref,
go look at F</usr/include/linux/joystick.h>.

=head1 AUTHOR

John Beppu (beppu@cpan.org)

=head1 SEE ALSO

Perl Modules:

L<Linux::Input>,

C Headers:

F</usr/include/linux/joystick.h>

Other Documentation:

F</usr/src/linux/Documentation/input/joystick.txt>

=cut

# vim:sw=2 sts=2 expandtab
# $Id: Joystick.pm,v 1.1 2004/10/13 07:09:55 beppu Exp $
