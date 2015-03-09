package AnyEvent::HTTPD::HTTPConnection;
use common::sense;
use IO::Handle;
use AnyEvent::Handle;
use Object::Event;
use Time::Local;

use AnyEvent::HTTPD::Util;

use Scalar::Util qw/weaken/;
our @ISA = qw/Object::Event/;

=head1 NAME

AnyEvent::HTTPD::HTTPConnection - A simple HTTP connection for request and response handling

=head1 DESCRIPTION

This class is a helper class for L<AnyEvent:HTTPD::HTTPServer> and L<AnyEvent::HTTPD>,
it handles TCP reading and writing as well as parsing and serializing
http requests.

It has no public interface yet.

=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{request_timeout} = 60
      unless defined $self->{request_timeout};

   $self->{hdl} =
      AnyEvent::Handle->new (
         fh       => $self->{fh},
         on_eof   => sub { $self->do_disconnect },
         on_error => sub { $self->do_disconnect ("Error: $!") },
         ($self->{ssl}
            ? (tls => "accept", tls_ctx => $self->{ssl})
            : ()),
      );

   $self->push_header_line;

   return $self
}

sub error {
   my ($self, $code, $msg, $hdr, $content) = @_;

   if ($code !~ /^(1\d\d|204|304)$/o) {
      unless (defined $content) { $content = "$code $msg\n" }
      $hdr->{'Content-Type'} = 'text/plain';
   }

   $self->response ($code, $msg, $hdr, $content);
}

sub response_done {
   my ($self) = @_;

   (delete $self->{transfer_cb})->() if $self->{transfer_cb};

   # sometimes a response might be written after connection is already dead:
   return unless defined ($self->{hdl}) && !$self->{disconnected};

   $self->{hdl}->on_drain; # clear any drain handlers

   if ($self->{keep_alive}) {
      $self->push_header_line;

   } else {
      $self->{hdl}->on_drain (sub { $self->do_disconnect });
   }
}

our @DoW = qw(Sun Mon Tue Wed Thu Fri Sat);
our @MoY = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
our %MoY;
@MoY{@MoY} = (1..12);

# Taken from HTTP::Date module of LWP.
sub _time_to_http_date
{
    my $time = shift;
    $time = time unless defined $time;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($time);

    sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
       $DoW[$wday],
       $mday, $MoY[$mon], $year + 1900,
       $hour, $min, $sec);
}


sub response {
   my ($self, $code, $msg, $hdr, $content, $no_body) = @_;
   return if $self->{disconnected};
   return unless $self->{hdl};

   my $res = "HTTP/1.0 $code $msg\015\012";
   header_set ($hdr, 'Date' => _time_to_http_date time)
      unless header_exists ($hdr, 'Date');
   header_set ($hdr, 'Expires' => header_get ($hdr, 'Date'))
      unless header_exists ($hdr, 'Expires');
   header_set ($hdr, 'Cache-Control' => "max-age=0")
      unless header_exists ($hdr, 'Cache-Control');
   header_set ($hdr, 'Connection' =>
                    ($self->{keep_alive} ? 'Keep-Alive' : 'close'));

   header_set ($hdr, 'Content-Length' => length "$content")
      unless header_exists ($hdr, 'Content-Length')
             || ref $content;

   unless (defined header_get ($hdr, 'Content-Length')) {
      # keep alive with no content length will NOT work.
      delete $self->{keep_alive};
      header_set ($hdr, 'Connection' => 'close');
   }

   while (my ($h, $v) = each %$hdr) {
      next unless defined $v;
      $res .= "$h: $v\015\012";
   }

   $res .= "\015\012";

   if ($no_body) { # for HEAD requests!
      $self->{hdl}->push_write ($res);
      $self->response_done;
      return;
   }

   if (ref ($content) eq 'CODE') {
      weaken $self;

      my $chunk_cb = sub {
         my ($chunk) = @_;

         return 0 unless defined ($self) && defined ($self->{hdl}) && !$self->{disconnected};

         delete $self->{transport_polled};

         if (defined ($chunk) && length ($chunk) > 0) {
            $self->{hdl}->push_write ($chunk);

         } else {
            $self->response_done;
         }

         return 1;
      };

      $self->{transfer_cb} = $content;

      $self->{hdl}->on_drain (sub {
         return unless $self;

         if (length $res) {
            my $r = $res;
            undef $res;
            $chunk_cb->($r);

         } elsif (not $self->{transport_polled}) {
            $self->{transport_polled} = 1;
            $self->{transfer_cb}->($chunk_cb) if $self;
         }
      });

   } else {
      $res .= $content;
      $self->{hdl}->push_write ($res);
      $self->response_done;
   }
}

sub _unquote {
   my ($str) = @_;
   if ($str =~ /^"(.*?)"$/o) {
      $str = $1;
      my $obo = '';
      while ($str =~ s/^(?:([^"]+)|\\(.))//so) {
        $obo .= $1;
      }
      $str = $obo;
   }
   $str
}

sub decode_part {
   my ($self, $hdr, $cont) = @_;

   $hdr = _parse_headers ($hdr);
   if ($hdr->{'content-disposition'} =~ /form-data|attachment/o) {
      my ($dat, @pars) = split /\s*;\s*/o, $hdr->{'content-disposition'};
      my @params;

      my %p;

      my @res;

      for my $name_para (@pars) {
         my ($name, $par) = split /\s*=\s*/o, $name_para;
         if ($par =~ /^".*"$/o) { $par = _unquote ($par) }
         $p{$name} = $par;
      }

      my ($ctype, $bound) = _content_type_boundary ($hdr->{'content-type'});

      if ($ctype eq 'multipart/mixed') {
         my $parts = $self->decode_multipart ($cont, $bound);
         for my $sp (keys %$parts) {
            for (@{$parts->{$sp}}) {
               push @res, [$p{name}, @$_];
            }
         }

      } else {
         push @res, [$p{name}, $cont, $hdr->{'content-type'}, $p{filename}];
      }

      return @res
   }

   ();
}

sub decode_multipart {
   my ($self, $cont, $boundary) = @_;

   my $parts = {};

   while ($cont =~ s/
      ^--\Q$boundary\E             \015?\012
      ((?:[^\015\012]+\015\012)* ) \015?\012
      (.*?)                        \015?\012
      (--\Q$boundary\E (--)?       \015?\012)
      /\3/xs) {
      my ($h, $c, $e) = ($1, $2, $4);

      if (my (@p) = $self->decode_part ($h, $c)) {
         for my $part (@p) {
            push @{$parts->{$part->[0]}}, [$part->[1], $part->[2], $part->[3]];
         }
      }

      last if $e eq '--';
   }

   return $parts;
}

# application/x-www-form-urlencoded
#
# This is the default content type. Forms submitted with this content type must
# be encoded as follows:
#
#    1. Control names and values are escaped. Space characters are replaced by
#    `+', and then reserved characters are escaped as described in [RFC1738],
#    section 2.2: Non-alphanumeric characters are replaced by `%HH', a percent
#    sign and two hexadecimal digits representing the ASCII code of the
#    character. Line breaks are represented as "CR LF" pairs (i.e., `%0D%0A').
#
#    2. The control names/values are listed in the order they appear in the
#    document. The name is separated from the value by `=' and name/value pairs
#    are separated from each other by `&'.
#

sub _content_type_boundary {
   my ($ctype) = @_;
   my ($c, @params) = split /\s*[;,]\s*/o, $ctype;
   my $bound;
   for (@params) {
      if (/^\s*boundary\s*=\s*(.*?)\s*$/o) {
         $bound = _unquote ($1);
      }
   }
   ($c, $bound)
}

sub handle_request {
   my ($self, $method, $uri, $hdr, $cont) = @_;

   $self->{keep_alive} = ($hdr->{connection} =~ /keep-alive/io);

   my ($ctype, $bound) = _content_type_boundary ($hdr->{'content-type'});

   if ($ctype eq 'multipart/form-data') {
      $cont = $self->decode_multipart ($cont, $bound);

   } elsif ($ctype =~ /x-www-form-urlencoded/o) {
      $cont = parse_urlencoded ($cont);
   }

   $self->event (request => $method, $uri, $hdr, $cont);
}

# loosely adopted from AnyEvent::HTTP:
sub _parse_headers {
   my ($header) = @_;
   my $hdr;

   $header =~ y/\015//d;

   while ($header =~ /\G
      ([^:\000-\037]+):
      [\011\040]*
      ( (?: [^\012]+ | \012 [\011\040] )* )
      \012
   /sgcxo) {

      $hdr->{lc $1} .= ",$2"
   }

   return undef unless $header =~ /\G$/sgxo;

   for (keys %$hdr) {
      substr $hdr->{$_}, 0, 1, '';
      # remove folding:
      $hdr->{$_} =~ s/\012([\011\040])/$1/sgo;
   }

   $hdr
}

sub push_header {
   my ($self, $hdl) = @_;

   $self->{hdl}->unshift_read (line =>
      qr{(?<![^\012])\015?\012}o,
      sub {
         my ($hdl, $data) = @_;
         my $hdr = _parse_headers ($data);

         unless (defined $hdr) {
            $self->error (599 => "garbled headers");
         }

         push @{$self->{last_header}}, $hdr;

         if (defined $hdr->{'content-length'}) {
            $self->{hdl}->unshift_read (chunk => $hdr->{'content-length'}, sub {
               my ($hdl, $data) = @_;
               $self->handle_request (@{$self->{last_header}}, $data);
            });
         } else {
            $self->handle_request (@{$self->{last_header}});
         }
      }
   );
}

sub push_header_line {
   my ($self) = @_;

   return if $self->{disconnected};

   weaken $self;

   $self->{req_timeout} =
      AnyEvent->timer (after => $self->{request_timeout}, cb => sub {
         return unless defined $self;

         $self->do_disconnect ("request timeout ($self->{request_timeout})");
      });

   $self->{hdl}->push_read (line => sub {
      my ($hdl, $line) = @_;
      return unless defined $self;

      delete $self->{req_timeout};

      if ($line =~ /(\S+) \040 (\S+) \040 HTTP\/(\d+)\.(\d+)/xso) {
         my ($meth, $url, $vm, $vi) = ($1, $2, $3, $4);

         if (not grep { $meth eq $_ } @{ $self->{allowed_methods} }) {
            $self->error (501, "not implemented",
                          { Allow => join(",", @{ $self->{allowed_methods} })});
            return;
         }

         if ($vm >= 2) {
            $self->error (506, "http protocol version not supported");
            return;
         }

         $self->{last_header} = [$meth, $url];
         $self->push_header;

      } elsif ($line eq '') {
         # ignore empty lines before requests, this prevents
         # browser bugs w.r.t. keep-alive (according to marc lehmann).
         $self->push_header_line;

      } else {
         $self->error (400 => 'bad request');
      }
   });
}

sub do_disconnect {
   my ($self, $err) = @_;

   return if $self->{disconnected};

   $self->{disconnected} = 1;
   $self->{transfer_cb}->() if $self->{transfer_cb};
   delete $self->{transfer_cb};
   delete $self->{req_timeout};
   $self->event ('disconnect', $err);
   shutdown $self->{hdl}->{fh}, 1;
   $self->{hdl}->on_read (sub { });
   $self->{hdl}->on_eof (undef);
   my $timer;
   $timer = AE::timer 2, 0, sub {
      undef $timer;
      delete $self->{hdl};
   };
}

1;
