package AnyEvent::HTTPD;
use common::sense;
use Scalar::Util qw/weaken/;
use URI;
use AnyEvent::HTTPD::Request;
use AnyEvent::HTTPD::Util;

use base qw/AnyEvent::HTTPD::HTTPServer/;

=head1 NAME

AnyEvent::HTTPD - A simple lightweight event based web (application) server

=head1 VERSION

Version 0.93

=cut

our $VERSION = '0.93';

=head1 SYNOPSIS

    use AnyEvent::HTTPD;

    my $httpd = AnyEvent::HTTPD->new (port => 9090);

    $httpd->reg_cb (
       '/' => sub {
          my ($httpd, $req) = @_;

          $req->respond ({ content => ['text/html',
             "<html><body><h1>Hello World!</h1>"
             . "<a href=\"/test\">another test page</a>"
             . "</body></html>"
          ]});
       },
       '/test' => sub {
          my ($httpd, $req) = @_;

          $req->respond ({ content => ['text/html',
             "<html><body><h1>Test page</h1>"
             . "<a href=\"/\">Back to the main page</a>"
             . "</body></html>"
          ]});
       },
    );

    $httpd->run; # making a AnyEvent condition variable would also work

=head1 DESCRIPTION

This module provides a simple HTTPD for serving simple web application
interfaces. It's completly event based and independend from any event loop
by using the L<AnyEvent> module.

It's HTTP implementation is a bit hacky, so before using this module make sure
it works for you and the expected deployment. Feel free to improve the HTTP
support and send in patches!

The documentation is currently only the source code, but next versions of this
module will be better documented hopefully. See also the C<samples/> directory
in the L<AnyEvent::HTTPD> distribution for basic starting points.

=head1 FEATURES

=over 4

=item * support for GET and POST requests.

=item * support for HTTP 1.0 keep-alive.

=item * processing of C<x-www-form-urlencoded> and C<multipart/form-data> (C<multipart/mixed>) encoded form parameters.

=item * support for streaming responses.

=item * with version 0.8 no more dependend on L<LWP> for L<HTTP::Date>.

=item * (limited) support for SSL

=back

=head1 METHODS

The L<AnyEvent::HTTPD> class inherits directly from
L<AnyEvent::HTTPD::HTTPServer> which inherits the event callback interface from
L<Object::Event>.

Event callbacks can be registered via the L<Object::Event> API (see the
documentation of L<Object::Event> for details).

For a list of available events see below in the I<EVENTS> section.

=over 4

=item B<new (%args)>

This is the constructor for a L<AnyEvent::HTTPD> object.
The C<%args> hash may contain one of these key/value pairs:

=over 4

=item host => $host

The TCP address of the HTTP server will listen on. Usually 0.0.0.0 (the
default), for a public server, or 127.0.0.1 for a local server.

=item port => $port

The TCP port the HTTP server will listen on. If undefined some
free port will be used. You can get it via the C<port> method.

=item ssl => $tls_ctx

If this option is given the server will listen for a SSL/TLS connection on the
configured port. As C<$tls_ctx> you can pass anything that you can pass as
C<tls_ctx> to an L<AnyEvent::Handle> object.

Example:

   my $httpd =
      AnyEvent::HTTPD->new (
         port => 443,
         ssl  => { cert_file => "/path/to/my/server_cert_and_key.pem" }
      );

Or:

   my $httpd =
      AnyEvent::HTTPD->new (
         port => 443,
         ssl  => AnyEvent::TLS->new (...),
      );

=item request_timeout => $seconds

This will set the request timeout for connections.
The default value is 60 seconds.

=item backlog => $int

The backlog argument defines the maximum length the queue of pending
connections may grow to.  The real maximum queue length will be 1.5 times more
than the value specified in the backlog argument.

See also C<man 2 listen>.

By default will be set by L<AnyEvent::Socket>C<::tcp_server> to C<128>.

=item connection_class => $class

This is a special parameter that you can use to pass your own connection class
to L<AnyEvent::HTTPD::HTTPServer>.  This is only of interest to you if you plan
to subclass L<AnyEvent::HTTPD::HTTPConnection>.

=item request_class => $class

This is a special parameter that you can use to pass your own request class
to L<AnyEvent::HTTPD>.  This is only of interest to you if you plan
to subclass L<AnyEvent::HTTPD::Request>.

=item allowed_methods => $arrayref

This parameter sets the allowed HTTP methods for requests, defaulting to GET,
HEAD and POST.  Each request received is matched against this list, and a
'501 not implemented' is returned if no match is found.  Requests using
disallowed handlers will never trigger callbacks.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (
      request_class => "AnyEvent::HTTPD::Request",
      @_
   );

   $self->reg_cb (
      connect => sub {
         my ($self, $con) = @_;

         weaken $self;

         $self->{conns}->{$con} = $con->reg_cb (
            request => sub {
               my ($con, $meth, $url, $hdr, $cont) = @_;
               #d# warn "REQUEST: $meth, $url, [$cont] " . join (',', %$hdr) . "\n";

               $url = URI->new ($url);

               if ($meth eq 'GET') {
                  $cont = parse_urlencoded ($url->query);
               }

               if ( scalar grep { $meth eq $_ } @{ $self->{allowed_methods} } ) {

                  weaken $con;

                  $self->handle_app_req (
                     $meth, $url, $hdr, $cont, $con->{host}, $con->{port},
                     sub {
                        $con->response (@_) if $con;
                     });
               } else {
                  $con->response (200, "ok");
               }
            }
         );

         $self->event (client_connected => $con->{host}, $con->{port});
      },
      disconnect => sub {
         my ($self, $con) = @_;
         $con->unreg_cb (delete $self->{conns}->{$con});
         $self->event (client_disconnected => $con->{host}, $con->{port});
      },
   );

   $self->{state} ||= {};

   return $self
}

sub handle_app_req {
   my ($self, $meth, $url, $hdr, $cont, $host, $port, $respcb) = @_;

   my $req =
      $self->{request_class}->new (
         httpd   => $self,
         method  => $meth,
         url     => $url,
         hdr     => $hdr,
         parm    => (ref $cont ? $cont : {}),
         content => (ref $cont ? undef : $cont),
         resp    => $respcb,
         host    => $host,
         port    => $port,
      );

   $self->{req_stop} = 0;
   $self->event (request => $req);
   return if $self->{req_stop};

   my @evs;
   my $cururl = '';
   for my $seg ($url->path_segments) {
      $cururl .= $seg;
      push @evs, $cururl;
      $cururl .= '/';
   }

   for my $ev (reverse @evs) {
      $self->event ($ev => $req);
      last if $self->{req_stop};
   }
}

=item B<port>

Returns the port number this server is bound to.

=item B<host>

Returns the host/ip this server is bound to.

=item B<allowed_methods>

Returns an arrayref of allowed HTTP methods, possibly as set by the
allowed_methods argument to the constructor.

=item B<stop_request>

When the server walks the request URI path upwards you can stop
the walk by calling this method. You can even stop further handling
after the C<request> event.

Example:

   $httpd->reg_cb (
      '/test' => sub {
         my ($httpd, $req) = @_;

         # ...

         $httpd->stop_request; # will prevent that the callback below is called
      },
      '' => sub { # this one wont be called by a request to '/test'
         my ($httpd, $req) = @_;

         # ...
      }
   );

=cut

sub stop_request {
   my ($self) = @_;
   $self->{req_stop} = 1;
}

=item B<run>

This method is a simplification of the C<AnyEvent> condition variable
idiom. You can use it instead of writing:

   my $cvar = AnyEvent->condvar;
   $cvar->wait;

=cut

sub run {
   my ($self) = @_;
   $self->{condvar} = AnyEvent->condvar;
   $self->{condvar}->wait;
}

=item B<stop>

This will stop the HTTP server and return from the
C<run> method B<if you started the server via that method!>

=cut

sub stop { $_[0]->{condvar}->broadcast if $_[0]->{condvar} }

=back

=head1 EVENTS

Every request goes to a specific URL. After a (GET or POST) request is
received the URL's path segments are walked down and for each segment
a event is generated. An example:

If the URL '/test/bla.jpg' is requestes following events will be generated:

  '/test/bla.jpg' - the event for the last segment
  '/test'         - the event for the 'test' segment
  ''              - the root event of each request

To actually handle any request you just have to register a callback for the event
name with the empty string. To handle all requests in the '/test' directory
you have to register a callback for the event with the name C<'/test'>.
Here is an example how to register an event for the example URL above:

   $httpd->reg_cb (
      '/test/bla.jpg' => sub {
         my ($httpd, $req) = @_;

         $req->respond ([200, 'ok', { 'Content-Type' => 'text/html' }, '<h1>Test</h1>' }]);
      }
   );

See also C<stop_request> about stopping the walk of the path segments.

The first argument to such a callback is always the L<AnyEvent::HTTPD> object
itself.  The second argument (C<$req>) is the L<AnyEvent::HTTPD::Request>
object for this request. It can be used to get the (possible) form parameters
for this request or the transmitted content and respond to the request.


Along with the above mentioned events these events are also provided:

=over 4

=item request => $req

Every request also emits the C<request> event, with the same arguments and
semantics as the above mentioned path request events.  You can use this to
implement your own request multiplexing. You can use C<stop_request> to stop
any further processing of the request as the C<request> event is the first
thing that is executed for an incoming request.

An example of one of many possible uses:

   $httpd->reg_cb (
      request => sub {
         my ($httpd, $req) = @_;

         my $url = $req->url;

         if ($url->path =~ /\/images\/img_(\d+).jpg$/) {
            handle_image_request ($req, $1); # your task :)

            # stop the request from emitting further events
            # so that the '/images/img_001.jpg' and the
            # '/images' and '' events are NOT emitted:
            $httpd->stop_request;
         }
      }
   );

=item client_connected => $host, $port

=item client_disconnected => $host, $port

These events are emitted whenever a client coming from C<$host:$port> connects
to your server or is disconnected from it.

=back

=head1 CACHING

Any response from the HTTP server will have C<Cache-Control> set to C<max-age=0> and
also the C<Expires> header set to the C<Date> header. Meaning: Caching is disabled.

You can of course set those headers yourself in the response, or remove them by
setting them to undef, but keep in mind that the default for those headers are
like mentioned above.

If you need more support here you can send me a mail or even better: a patch :)

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-bs-httpd at rt.cpan.org>,
or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=AnyEvent-HTTPD>.  I will be
notified, and then you'll automatically be notified of progress on your bug as
I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc AnyEvent::HTTPD


You can also look for information at:

=over 4

=item * Git repository

L<http://git.ta-sa.org/AnyEvent-HTTPD.git>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-HTTPD>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/AnyEvent-HTTPD>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/AnyEvent-HTTPD>

=item * Search CPAN

L<http://search.cpan.org/dist/AnyEvent-HTTPD>

=back

=head1 ACKNOWLEDGEMENTS

   Andrey Smirnov   - for keep-alive patches.
   Pedro Melo       - for valuable input in general and patches.
   Nicholas Harteau - patch for ';' pair separator support,
                      patch for allowed_methods support
   Chris Kastorff   - patch for making default headers removable
                      and more fault tolerant w.r.t. case.
   Mons Anderson    - Optimizing the regexes in L<AnyEvent::HTTPD::HTTPConnection>
                      and adding the C<backlog> option to L<AnyEvent::HTTPD>.

=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of AnyEvent::HTTPD
