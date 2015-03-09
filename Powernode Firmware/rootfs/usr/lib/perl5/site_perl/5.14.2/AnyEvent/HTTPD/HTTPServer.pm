package AnyEvent::HTTPD::HTTPServer;
use common::sense;
use Scalar::Util qw/weaken/;
use Object::Event;
use AnyEvent::Handle;
use AnyEvent::Socket;

use AnyEvent::HTTPD::HTTPConnection;

our @ISA = qw/Object::Event/;

=head1 NAME

AnyEvent::HTTPD::HTTPServer - A simple and plain http server

=head1 DESCRIPTION

This class handles incoming TCP connections for HTTP clients.
It's used by L<AnyEvent::HTTPD> to do it's job.

It has no public interface yet.

=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = {
      connection_class => "AnyEvent::HTTPD::HTTPConnection",
      allowed_methods  => [ qw/GET HEAD POST/ ],
      @_,
   };
   bless $self, $class;

   my $rself = $self;

   weaken $self;

   $self->{srv} =
      tcp_server $self->{host}, $self->{port}, sub {
         my ($fh, $host, $port) = @_;

         unless ($fh) {
            $self->event (error => "couldn't accept client: $!");
            return;
         }

         $self->accept_connection ($fh, $host, $port);
      }, sub {
         my ($fh, $host, $port) = @_;
         $self->{real_port} = $port;
         $self->{real_host} = $host;
         return $self->{backlog};
      };

   return $self
}

sub port { $_[0]->{real_port} }

sub host { $_[0]->{real_host} }

sub allowed_methods { $_[0]->{allowed_methods} }

sub accept_connection {
   my ($self, $fh, $h, $p) = @_;

   my $htc =
      $self->{connection_class}->new (
         fh => $fh,
         request_timeout => $self->{request_timeout},
         allowed_methods => $self->{allowed_methods},
         ssl => $self->{ssl},
         host => $h,
         port => $p);

   $self->{handles}->{$htc} = $htc;

   weaken $self;

   $htc->reg_cb (disconnect => sub {
      if (defined $self) {
         delete $self->{handles}->{$_[0]};
         $self->event (disconnect => $_[0], $_[1]);
      }
   });

   $self->event (connect => $htc);
}

1;
