package AnyEvent::HTTPD::Util;
use AnyEvent;
use AnyEvent::Socket;
use common::sense;

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT = qw/parse_urlencoded url_unescape header_set
                 header_get header_exists/;

=head1 NAME

AnyEvent::HTTPD::Util - Utility functions for AnyEvent::HTTPD

=head1 SYNOPSIS

=head1 DESCRIPTION

The functions in this package are not public.

=over 4

=cut

sub url_unescape {
   my ($val) = @_;
   $val =~ s/\+/\040/g;
   $val =~ s/%([0-9a-fA-F][0-9a-fA-F])/chr (hex ($1))/eg;
   $val
}

sub parse_urlencoded {
   my ($cont) = @_;
   my (@pars) = split /[\&\;]/, $cont;
   $cont = {};

   for (@pars) {
      my ($name, $val) = split /=/, $_;
      $name = url_unescape ($name);
      $val  = url_unescape ($val);

      push @{$cont->{$name}}, [$val, ''];
   }
   $cont
}

sub test_connect {
   my ($host, $port, $data) = @_;

   my $c = AE::cv;

   my $t; $t = AnyEvent->timer (after => 0.1, cb => sub {
      my $hdl;
      my $buf;
      undef $t;
      tcp_connect $host, $port, sub {
         my ($fh) = @_
            or die "couldn't connect: $!";

         $hdl =
            AnyEvent::Handle->new (
               fh => $fh,
               timeout => 15,
               on_eof => sub {
                  $c->send ($buf);
                  undef $hdl;
               },
               on_timeout => sub {
                  warn "test_connect timed out";
                  $c->send ($buf);
                  undef $hdl;
               },
               on_read => sub {
                  $buf .= $hdl->rbuf;
                  $hdl->rbuf = '';
               });
         $hdl->push_write ($data);
      };
   });

   $c
}

###
# these functions set/get/check existence of a header name:value pair while
# ignoring the case of the name
#
# quick hack, does not scale to large hashes. however, it's not expected to be
# run on large hashes.
#
# a more performant alternative would be to keep two hashes for each set of
# headers, one for the headers in the case they like, and one a mapping of
# names from some consistent form (say, all lowercase) to the name in the other
# hash, including capitalization. (this style is used in HTTP::Headers)

sub _header_transform_case_insens {
   my $lname = lc $_[1];
   my (@names) = grep { $lname eq lc ($_) } keys %{$_[0]};
   @names ? $names[0] : $_[1]
}

sub header_set {
    my ($hdrs, $name, $value) = @_;
    $name = _header_transform_case_insens ($hdrs, $name);
    $hdrs->{$name} = $value;
}

sub header_get {
    my ($hdrs, $name) = @_;
    $name = _header_transform_case_insens ($hdrs, $name);
    exists $hdrs->{$name} ? $hdrs->{$name} : undef
}

sub header_exists {
    my ($hdrs, $name) = @_;
    $name = _header_transform_case_insens ($hdrs, $name);
    # NB: even if the value is undefined, return true
    return exists $hdrs->{$name}
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009-2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

