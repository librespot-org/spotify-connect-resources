=head1 NAME

AnyEvent::HTTP - simple but non-blocking HTTP/HTTPS client

=head1 SYNOPSIS

   use AnyEvent::HTTP;

   http_get "http://www.nethype.de/", sub { print $_[1] };

   # ... do something else here

=head1 DESCRIPTION

This module is an L<AnyEvent> user, you need to make sure that you use and
run a supported event loop.

This module implements a simple, stateless and non-blocking HTTP
client. It supports GET, POST and other request methods, cookies and more,
all on a very low level. It can follow redirects supports proxies and
automatically limits the number of connections to the values specified in
the RFC.

It should generally be a "good client" that is enough for most HTTP
tasks. Simple tasks should be simple, but complex tasks should still be
possible as the user retains control over request and response headers.

The caller is responsible for authentication management, cookies (if
the simplistic implementation in this module doesn't suffice), referer
and other high-level protocol details for which this module offers only
limited support.

=head2 METHODS

=over 4

=cut

package AnyEvent::HTTP;

use strict;
no warnings;

use Errno ();

use AnyEvent 5.0 ();
use AnyEvent::Util ();
use AnyEvent::Socket ();
use AnyEvent::Handle ();

use base Exporter::;

our $VERSION = '1.46';

our @EXPORT = qw(http_get http_post http_head http_request);

our $USERAGENT          = "Mozilla/5.0 (compatible; U; AnyEvent-HTTP/$VERSION; +http://software.schmorp.de/pkg/AnyEvent)";
our $MAX_RECURSE        =  10;
our $MAX_PERSISTENT     =   8;
our $PERSISTENT_TIMEOUT =   2;
our $TIMEOUT            = 300;

# changing these is evil
our $MAX_PERSISTENT_PER_HOST = 0;
our $MAX_PER_HOST       = 4;

our $PROXY;
our $ACTIVE = 0;

my %KA_COUNT; # number of open keep-alive connections per host
my %CO_SLOT;  # number of open connections, and wait queue, per host

=item http_get $url, key => value..., $cb->($data, $headers)

Executes an HTTP-GET request. See the http_request function for details on
additional parameters and the return value.

=item http_head $url, key => value..., $cb->($data, $headers)

Executes an HTTP-HEAD request. See the http_request function for details
on additional parameters and the return value.

=item http_post $url, $body, key => value..., $cb->($data, $headers)

Executes an HTTP-POST request with a request body of C<$body>. See the
http_request function for details on additional parameters and the return
value.

=item http_request $method => $url, key => value..., $cb->($data, $headers)

Executes a HTTP request of type C<$method> (e.g. C<GET>, C<POST>). The URL
must be an absolute http or https URL.

When called in void context, nothing is returned. In other contexts,
C<http_request> returns a "cancellation guard" - you have to keep the
object at least alive until the callback get called. If the object gets
destroyed before the callbakc is called, the request will be cancelled.

The callback will be called with the response body data as first argument
(or C<undef> if an error occured), and a hash-ref with response headers as
second argument.

All the headers in that hash are lowercased. In addition to the response
headers, the "pseudo-headers" (uppercase to avoid clashing with possible
response headers) C<HTTPVersion>, C<Status> and C<Reason> contain the
three parts of the HTTP Status-Line of the same name.

The pseudo-header C<URL> contains the actual URL (which can differ from
the requested URL when following redirects - for example, you might get
an error that your URL scheme is not supported even though your URL is a
valid http URL because it redirected to an ftp URL, in which case you can
look at the URL pseudo header).

The pseudo-header C<Redirect> only exists when the request was a result
of an internal redirect. In that case it is an array reference with
the C<($data, $headers)> from the redirect response. Note that this
response could in turn be the result of a redirect itself, and C<<
$headers->{Redirect}[1]{Redirect} >> will then contain the original
response, and so on.

If the server sends a header multiple times, then their contents will be
joined together with a comma (C<,>), as per the HTTP spec.

If an internal error occurs, such as not being able to resolve a hostname,
then C<$data> will be C<undef>, C<< $headers->{Status} >> will be C<59x>
(usually C<599>) and the C<Reason> pseudo-header will contain an error
message.

A typical callback might look like this:

   sub {
      my ($body, $hdr) = @_;

      if ($hdr->{Status} =~ /^2/) {
         ... everything should be ok
      } else {
         print "error, $hdr->{Status} $hdr->{Reason}\n";
      }
   }

Additional parameters are key-value pairs, and are fully optional. They
include:

=over 4

=item recurse => $count (default: $MAX_RECURSE)

Whether to recurse requests or not, e.g. on redirects, authentication
retries and so on, and how often to do so.

=item headers => hashref

The request headers to use. Currently, C<http_request> may provide its
own C<Host:>, C<Content-Length:>, C<Connection:> and C<Cookie:> headers
and will provide defaults for C<User-Agent:> and C<Referer:> (this can be
suppressed by using C<undef> for these headers in which case they won't be
sent at all).

=item timeout => $seconds

The time-out to use for various stages - each connect attempt will reset
the timeout, as will read or write activity, i.e. this is not an overall
timeout.

Default timeout is 5 minutes.

=item proxy => [$host, $port[, $scheme]] or undef

Use the given http proxy for all requests. If not specified, then the
default proxy (as specified by C<$ENV{http_proxy}>) is used.

C<$scheme> must be either missing, C<http> for HTTP or C<https> for
HTTPS.

=item body => $string

The request body, usually empty. Will be-sent as-is (future versions of
this module might offer more options).

=item cookie_jar => $hash_ref

Passing this parameter enables (simplified) cookie-processing, loosely
based on the original netscape specification.

The C<$hash_ref> must be an (initially empty) hash reference which will
get updated automatically. It is possible to save the cookie_jar to
persistent storage with something like JSON or Storable, but this is not
recommended, as expiry times are currently being ignored.

Note that this cookie implementation is not of very high quality, nor
meant to be complete. If you want complete cookie management you have to
do that on your own. C<cookie_jar> is meant as a quick fix to get some
cookie-using sites working. Cookies are a privacy disaster, do not use
them unless required to.

=item tls_ctx => $scheme | $tls_ctx

Specifies the AnyEvent::TLS context to be used for https connections. This
parameter follows the same rules as the C<tls_ctx> parameter to
L<AnyEvent::Handle>, but additionally, the two strings C<low> or
C<high> can be specified, which give you a predefined low-security (no
verification, highest compatibility) and high-security (CA and common-name
verification) TLS context.

The default for this option is C<low>, which could be interpreted as "give
me the page, no matter what".

=item on_prepare => $callback->($fh)

In rare cases you need to "tune" the socket before it is used to
connect (for exmaple, to bind it on a given IP address). This parameter
overrides the prepare callback passed to C<AnyEvent::Socket::tcp_connect>
and behaves exactly the same way (e.g. it has to provide a
timeout). See the description for the C<$prepare_cb> argument of
C<AnyEvent::Socket::tcp_connect> for details.

=item on_header => $callback->($headers)

When specified, this callback will be called with the header hash as soon
as headers have been successfully received from the remote server (not on
locally-generated errors).

It has to return either true (in which case AnyEvent::HTTP will continue),
or false, in which case AnyEvent::HTTP will cancel the download (and call
the finish callback with an error code of C<598>).

This callback is useful, among other things, to quickly reject unwanted
content, which, if it is supposed to be rare, can be faster than first
doing a C<HEAD> request.

Example: cancel the request unless the content-type is "text/html".

   on_header => sub {
      $_[0]{"content-type"} =~ /^text\/html\s*(?:;|$)/
   },

=item on_body => $callback->($partial_body, $headers)

When specified, all body data will be passed to this callback instead of
to the completion callback. The completion callback will get the empty
string instead of the body data.

It has to return either true (in which case AnyEvent::HTTP will continue),
or false, in which case AnyEvent::HTTP will cancel the download (and call
the completion callback with an error code of C<598>).

This callback is useful when the data is too large to be held in memory
(so the callback writes it to a file) or when only some information should
be extracted, or when the body should be processed incrementally.

It is usually preferred over doing your own body handling via
C<want_body_handle>, but in case of streaming APIs, where HTTP is
only used to create a connection, C<want_body_handle> is the better
alternative, as it allows you to install your own event handler, reducing
resource usage.

=item want_body_handle => $enable

When enabled (default is disabled), the behaviour of AnyEvent::HTTP
changes considerably: after parsing the headers, and instead of
downloading the body (if any), the completion callback will be
called. Instead of the C<$body> argument containing the body data, the
callback will receive the L<AnyEvent::Handle> object associated with the
connection. In error cases, C<undef> will be passed. When there is no body
(e.g. status C<304>), the empty string will be passed.

The handle object might or might not be in TLS mode, might be connected to
a proxy, be a persistent connection etc., and configured in unspecified
ways. The user is responsible for this handle (it will not be used by this
module anymore).

This is useful with some push-type services, where, after the initial
headers, an interactive protocol is used (typical example would be the
push-style twitter API which starts a JSON/XML stream).

If you think you need this, first have a look at C<on_body>, to see if
that doesn't solve your problem in a better way.

=back

Example: make a simple HTTP GET request for http://www.nethype.de/

   http_request GET => "http://www.nethype.de/", sub {
      my ($body, $hdr) = @_;
      print "$body\n";
   };

Example: make a HTTP HEAD request on https://www.google.com/, use a
timeout of 30 seconds.

   http_request
      GET     => "https://www.google.com",
      timeout => 30,
      sub {
         my ($body, $hdr) = @_;
         use Data::Dumper;
         print Dumper $hdr;
      }
   ;

Example: make another simple HTTP GET request, but immediately try to
cancel it.

   my $request = http_request GET => "http://www.nethype.de/", sub {
      my ($body, $hdr) = @_;
      print "$body\n";
   };

   undef $request;

=cut

sub _slot_schedule;
sub _slot_schedule($) {
   my $host = shift;

   while ($CO_SLOT{$host}[0] < $MAX_PER_HOST) {
      if (my $cb = shift @{ $CO_SLOT{$host}[1] }) {
         # somebody wants that slot
         ++$CO_SLOT{$host}[0];
         ++$ACTIVE;

         $cb->(AnyEvent::Util::guard {
            --$ACTIVE;
            --$CO_SLOT{$host}[0];
            _slot_schedule $host;
         });
      } else {
         # nobody wants the slot, maybe we can forget about it
         delete $CO_SLOT{$host} unless $CO_SLOT{$host}[0];
         last;
      }
   }
}

# wait for a free slot on host, call callback
sub _get_slot($$) {
   push @{ $CO_SLOT{$_[0]}[1] }, $_[1];

   _slot_schedule $_[0];
}

our $qr_nlnl = qr{(?<![^\012])\015?\012};

our $TLS_CTX_LOW  = { cache => 1, sslv2 => 1 };
our $TLS_CTX_HIGH = { cache => 1, verify => 1, verify_peername => "https" };

sub http_request($$@) {
   my $cb = pop;
   my ($method, $url, %arg) = @_;

   my %hdr;

   $arg{tls_ctx} = $TLS_CTX_LOW  if $arg{tls_ctx} eq "low" || !exists $arg{tls_ctx};
   $arg{tls_ctx} = $TLS_CTX_HIGH if $arg{tls_ctx} eq "high";

   $method = uc $method;

   if (my $hdr = $arg{headers}) {
      while (my ($k, $v) = each %$hdr) {
         $hdr{lc $k} = $v;
      }
   }

   # pseudo headers for all subsequent responses
   my @pseudo = (URL => $url);
   push @pseudo, Redirect => delete $arg{Redirect} if exists $arg{Redirect};

   my $handle_class = 'AnyEvent::Handle';
   if (exists $arg{handle_class}) {
      $handle_class = $arg{handle_class};
      eval "require $handle_class";
      return $cb->(undef, { Status => 599, Reason => $@, @pseudo }) if $@;
   }

   my $recurse = exists $arg{recurse} ? delete $arg{recurse} : $MAX_RECURSE;

   return $cb->(undef, { Status => 599, Reason => "Too many redirections", @pseudo })
      if $recurse < 0;

   my $proxy   = $arg{proxy}   || $PROXY;
   my $timeout = $arg{timeout} || $TIMEOUT;

   my ($uscheme, $uauthority, $upath, $query, $fragment) =
      $url =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:(\?[^#]*))?(?:#(.*))?|;

   $uscheme = lc $uscheme;

   my $uport = $uscheme eq "http"  ?  80
             : $uscheme eq "https" ? 443
             : return $cb->(undef, { Status => 599, Reason => "Only http and https URL schemes supported", @pseudo });

   $uauthority =~ /^(?: .*\@ )? ([^\@:]+) (?: : (\d+) )?$/x
      or return $cb->(undef, { Status => 599, Reason => "Unparsable URL", @pseudo });

   my $uhost = $1;
   $uport = $2 if defined $2;

   $hdr{host} = defined $2 ? "$uhost:$2" : "$uhost"
      unless exists $hdr{host};

   $uhost =~ s/^\[(.*)\]$/$1/;
   $upath .= $query if length $query;

   $upath =~ s%^/?%/%;

   # cookie processing
   if (my $jar = $arg{cookie_jar}) {
      %$jar = () if $jar->{version} != 1;
 
      my @cookie;
 
      while (my ($chost, $v) = each %$jar) {
         if ($chost =~ /^\./) {
            next unless $chost eq substr $uhost, -length $chost;
         } elsif ($chost =~ /\./) {
            next unless $chost eq $uhost;
         } else {
            next;
         }
 
         while (my ($cpath, $v) = each %$v) {
            next unless $cpath eq substr $upath, 0, length $cpath;
 
            while (my ($k, $v) = each %$v) {
               next if $uscheme ne "https" && exists $v->{secure};
               my $value = $v->{value};
               $value =~ s/([\\"])/\\$1/g;
               $value = '"'.$value.'"' if $value =~ m%["\\=;,[:space:]]%;
               push @cookie, "$k=$value";
            }
         }
      }
 
      $hdr{cookie} = join "; ", @cookie
         if @cookie;
   }

   my ($rhost, $rport, $rscheme, $rpath); # request host, port, path

   if ($proxy) {
      ($rpath, $rhost, $rport, $rscheme) = ($url, @$proxy);

      $rscheme = "http" unless defined $rscheme;

      # don't support https requests over https-proxy transport,
      # can't be done with tls as spec'ed, unless you double-encrypt.
      $rscheme = "http" if $uscheme eq "https" && $rscheme eq "https";
   } else {
      ($rhost, $rport, $rscheme, $rpath) = ($uhost, $uport, $uscheme, $upath);
   }

   # leave out fragment and query string, just a heuristic
   $hdr{referer}      ||= "$uscheme://$uauthority$upath" unless exists $hdr{referer};
   $hdr{"user-agent"} ||= $USERAGENT                     unless exists $hdr{"user-agent"};

   $hdr{"content-length"} = length $arg{body}
      if length $arg{body} || $method ne "GET";

   my %state = (connect_guard => 1);

   _get_slot $uhost, sub {
      $state{slot_guard} = shift;

      return unless $state{connect_guard};

      $state{connect_guard} = AnyEvent::Socket::tcp_connect $rhost, $rport, sub {
         $state{fh} = shift
            or do {
               my $err = "$!";
               %state = ();
               return $cb->(undef, { Status => 599, Reason => $err, @pseudo });
            };

         pop; # free memory, save a tree

         return unless delete $state{connect_guard};

         # get handle
         $state{handle} = new $handle_class
            fh       => $state{fh},
            peername => $rhost,
            tls_ctx  => $arg{tls_ctx},
            # these need to be reconfigured on keepalive handles
            timeout  => $timeout,
            on_error => sub {
               %state = ();
               $cb->(undef, { Status => 599, Reason => $_[2], @pseudo });
            },
            on_eof   => sub {
               %state = ();
               $cb->(undef, { Status => 599, Reason => "Unexpected end-of-file", @pseudo });
            },
         ;

         # limit the number of persistent connections
         # keepalive not yet supported
#         if ($KA_COUNT{$_[1]} < $MAX_PERSISTENT_PER_HOST) {
#            ++$KA_COUNT{$_[1]};
#            $state{handle}{ka_count_guard} = AnyEvent::Util::guard {
#               --$KA_COUNT{$_[1]}
#            };
#            $hdr{connection} = "keep-alive";
#         } else {
            delete $hdr{connection};
#         }

         $state{handle}->starttls ("connect") if $rscheme eq "https";

         # handle actual, non-tunneled, request
         my $handle_actual_request = sub {
            $state{handle}->starttls ("connect") if $uscheme eq "https" && !exists $state{handle}{tls};

            # send request
            $state{handle}->push_write (
               "$method $rpath HTTP/1.0\015\012"
               . (join "", map "\u$_: $hdr{$_}\015\012", grep defined $hdr{$_}, keys %hdr)
               . "\015\012"
               . (delete $arg{body})
            );

            # return if error occured during push_write()
            return unless %state;

            %hdr = (); # reduce memory usage, save a kitten, also make it possible to re-use

            # status line and headers
            $state{handle}->push_read (line => $qr_nlnl, sub {
               for ("$_[1]") {
                  y/\015//d; # weed out any \015, as they show up in the weirdest of places.

                  /^(?:HTTP|ICY)(?:\/([0-9\.]+))? \s+ ([0-9]{3}) (?: \s+ ([^\015\012]*) )? \015?\012/igxc
                     or return (%state = (), $cb->(undef, { Status => 599, Reason => "Invalid server response", @pseudo }));

                  push @pseudo,
                     HTTPVersion => $1,
                     Status      => $2,
                     Reason      => $3,
                  ;

                  # things seen, not parsed:
                  # p3pP="NON CUR OTPi OUR NOR UNI"

                  $hdr{lc $1} .= ",$2"
                     while /\G
                           ([^:\000-\037]*):
                           [\011\040]*
                           ((?: [^\012]+ | \012[\011\040] )*)
                           \012
                        /gxc;

                  /\G$/
                    or return (%state = (), $cb->(undef, { Status => 599, Reason => "Garbled response headers", @pseudo }));
               }

               # remove the "," prefix we added to all headers above
               substr $_, 0, 1, ""
                  for values %hdr;

               # patch in all pseudo headers
               %hdr = (%hdr, @pseudo);

               # redirect handling
               # microsoft and other shitheads don't give a shit for following standards,
               # try to support some common forms of broken Location headers.
               if ($hdr{location} !~ /^(?: $ | [^:\/?\#]+ : )/x) {
                  $hdr{location} =~ s/^\.\/+//;

                  my $url = "$rscheme://$uhost:$uport";

                  unless ($hdr{location} =~ s/^\///) {
                     $url .= $upath;
                     $url =~ s/\/[^\/]*$//;
                  }

                  $hdr{location} = "$url/$hdr{location}";
               }

               my $redirect;

               if ($recurse) {
                  my $status = $hdr{Status};

                  # industry standard is to redirect POST as GET for
                  # 301, 302 and 303, in contrast to http/1.0 and 1.1.
                  # also, the UA should ask the user for 301 and 307 and POST,
                  # industry standard seems to be to simply follow.
                  # we go with the industry standard.
                  if ($status == 301 or $status == 302 or $status == 303) {
                     # HTTP/1.1 is unclear on how to mutate the method
                     $method = "GET" unless $method eq "HEAD";
                     $redirect = 1;
                  } elsif ($status == 307) {
                     $redirect = 1;
                  }
               }

               my $finish = sub {
                  $state{handle}->destroy if $state{handle};
                  %state = ();

                  # set-cookie processing
                  if ($arg{cookie_jar}) {
                     for ($_[1]{"set-cookie"}) {
                        # parse NAME=VALUE
                        my @kv;

					    # AWY - updated from AnyEvent::HTTP 2.15
					    # expires is not http-compliant in the original cookie-spec,
					    # we support the official date format and some extensions
					    while (
					       m{
					          \G\s*
					          (?:
					             expires \s*=\s* ([A-Z][a-z][a-z]+,\ [^,;]+)
					             | ([^=;,[:space:]]+) (?: \s*=\s* (?: "((?:[^\\"]+|\\.)*)" | ([^;,[:space:]]*) ) )?
					          )
					       }gcxsi
					    ) {
					       my $name = $2;
					       my $value = $4;
					
					       if (defined $1) {
					          # expires
					          $name  = "expires";
					          $value = $1;
					       } elsif (defined $3) {
					          # quoted
					          $value = $3;
					          $value =~ s/\\(.)/$1/gs;
					       }
					
					       push @kv, @kv ? lc $name : $name, $value;
					
					       last unless /\G\s*;/gc;
					    }

                        last unless @kv;

                        my $name = shift @kv;
                        my %kv = (value => shift @kv, @kv);

                        my $cdom;
                        my $cpath = (delete $kv{path}) || "/";

                        if (exists $kv{domain}) {
                           $cdom = delete $kv{domain};
    
                           $cdom =~ s/^\.?/./; # make sure it starts with a "."

                           next if $cdom =~ /\.$/;
       
                           # this is not rfc-like and not netscape-like. go figure.
                           my $ndots = $cdom =~ y/.//;
                           next if $ndots < ($cdom =~ /\.[^.][^.]\.[^.][^.]$/ ? 3 : 2);
                        } else {
                           $cdom = $uhost;
                        }
    
                        # store it
                        $arg{cookie_jar}{version} = 1;
                        $arg{cookie_jar}{$cdom}{$cpath}{$name} = \%kv;

                        redo if /\G\s*,/gc;
                     }
                  }

                  if ($redirect && exists $hdr{location}) {
                     # we ignore any errors, as it is very common to receive
                     # Content-Length != 0 but no actual body
                     # we also access %hdr, as $_[1] might be an erro
                     http_request (
                        $method  => $hdr{location},
                        %arg,
                        recurse  => $recurse - 1,
                        Redirect => \@_,
                        $cb);
                  } else {
                     $cb->($_[0], $_[1]);
                  }
               };

               my $len = $hdr{"content-length"};

               if (!$redirect && $arg{on_header} && !$arg{on_header}(\%hdr)) {
                  $finish->(undef, { Status => 598, Reason => "Request cancelled by on_header", @pseudo });
               } elsif (
                  $hdr{Status} =~ /^(?:1..|[23]04)$/
                  or $method eq "HEAD"
                  or (defined $len && !$len)
               ) {
                  # no body
                  $finish->("", \%hdr);
               } else {
                  # body handling, four different code paths
                  # for want_body_handle, on_body (2x), normal (2x)
                  # we might read too much here, but it does not matter yet (no pers. connections)
                  if (!$redirect && $arg{want_body_handle}) {
                     $_[0]->on_eof   (undef);
                     $_[0]->on_error (undef);
                     $_[0]->on_read  (undef);

                     $finish->(delete $state{handle}, \%hdr);

                  } elsif ($arg{on_body}) {
                     $_[0]->on_error (sub { $finish->(undef, { Status => 599, Reason => $_[2], @pseudo }) });
                     if ($len) {
                        $_[0]->on_eof (undef);
                        $_[0]->on_read (sub {
                           $len -= length $_[0]{rbuf};

                           $arg{on_body}(delete $_[0]{rbuf}, \%hdr)
                              or $finish->(undef, { Status => 598, Reason => "Request cancelled by on_body", @pseudo });

                           $len > 0
                              or $finish->("", \%hdr);
                        });
                     } else {
                        $_[0]->on_eof (sub {
                           $finish->("", \%hdr);
                        });
                        $_[0]->on_read (sub {
                           $arg{on_body}(delete $_[0]{rbuf}, \%hdr)
                              or $finish->(undef, { Status => 598, Reason => "Request cancelled by on_body", @pseudo });
                        });
                     }
                  } else {
                     $_[0]->on_eof (undef);

                     if ($len) {
                        $_[0]->on_error (sub { $finish->(undef, { Status => 599, Reason => $_[2], @pseudo }) });
                        $_[0]->on_read (sub {
                           $finish->((substr delete $_[0]{rbuf}, 0, $len, ""), \%hdr)
                              if $len <= length $_[0]{rbuf};
                        });
                     } else {
                        $_[0]->on_error (sub {
                           ($! == Errno::EPIPE || !$!)
                              ? $finish->(delete $_[0]{rbuf}, \%hdr)
                              : $finish->(undef, { Status => 599, Reason => $_[2], @pseudo });
                        });
                        $_[0]->on_read (sub { });
                     }
                  }
               }
            });
         };

         # now handle proxy-CONNECT method
         if ($proxy && $uscheme eq "https") {
            # oh dear, we have to wrap it into a connect request

            # maybe re-use $uauthority with patched port?
            $state{handle}->push_write ("CONNECT $uhost:$uport HTTP/1.0\015\012Host: $uhost\015\012\015\012");
            $state{handle}->push_read (line => $qr_nlnl, sub {
               $_[1] =~ /^HTTP\/([0-9\.]+) \s+ ([0-9]{3}) (?: \s+ ([^\015\012]*) )?/ix
                  or return (%state = (), $cb->(undef, { Status => 599, Reason => "Invalid proxy connect response ($_[1])", @pseudo }));

               if ($2 == 200) {
                  $rpath = $upath;
                  &$handle_actual_request;
               } else {
                  %state = ();
                  $cb->(undef, { Status => $2, Reason => $3, @pseudo });
               }
            });
         } else {
            &$handle_actual_request;
         }

      }, $arg{on_prepare} || sub { $timeout };
   };

   defined wantarray && AnyEvent::Util::guard { %state = () }
}

sub http_get($@) {
   unshift @_, "GET";
   &http_request
}

sub http_head($@) {
   unshift @_, "HEAD";
   &http_request
}

sub http_post($$@) {
   my $url = shift;
   unshift @_, "POST", $url, "body";
   &http_request
}

=back

=head2 DNS CACHING

AnyEvent::HTTP uses the AnyEvent::Socket::tcp_connect function for
the actual connection, which in turn uses AnyEvent::DNS to resolve
hostnames. The latter is a simple stub resolver and does no caching
on its own. If you want DNS caching, you currently have to provide
your own default resolver (by storing a suitable resolver object in
C<$AnyEvent::DNS::RESOLVER>).

=head2 GLOBAL FUNCTIONS AND VARIABLES

=over 4

=item AnyEvent::HTTP::set_proxy "proxy-url"

Sets the default proxy server to use. The proxy-url must begin with a
string of the form C<http://host:port> (optionally C<https:...>), croaks
otherwise.

To clear an already-set proxy, use C<undef>.

=item $AnyEvent::HTTP::MAX_RECURSE

The default value for the C<recurse> request parameter (default: C<10>).

=item $AnyEvent::HTTP::USERAGENT

The default value for the C<User-Agent> header (the default is
C<Mozilla/5.0 (compatible; U; AnyEvent-HTTP/$VERSION; +http://software.schmorp.de/pkg/AnyEvent)>).

=item $AnyEvent::HTTP::MAX_PER_HOST

The maximum number of concurrent connections to the same host (identified
by the hostname). If the limit is exceeded, then the additional requests
are queued until previous connections are closed.

The default value for this is C<4>, and it is highly advisable to not
increase it.

=item $AnyEvent::HTTP::ACTIVE

The number of active connections. This is not the number of currently
running requests, but the number of currently open and non-idle TCP
connections. This number of can be useful for load-leveling.

=back

=cut

sub set_proxy($) {
   if (length $_[0]) {
      $_[0] =~ m%^(https?):// ([^:/]+) (?: : (\d*) )?%ix
         or Carp::croak "$_[0]: invalid proxy URL";
      $PROXY = [$2, $3 || 3128, $1]
   } else {
      undef $PROXY;
   }
}

# initialise proxy from environment
eval {
   set_proxy $ENV{http_proxy};
};

=head1 SEE ALSO

L<AnyEvent>.

=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://home.schmorp.de/

With many thanks to Дмитрий Шалашов, who provided countless
testcases and bugreports.

=cut

1

