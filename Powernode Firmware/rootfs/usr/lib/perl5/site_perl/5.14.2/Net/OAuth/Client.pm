package Net::OAuth::Client;
use warnings;
use strict;
use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw/id secret callback is_v1a user_agent site debug session/);
use LWP::UserAgent;
use URI;
use Net::OAuth;
use Net::OAuth::Message;
use Net::OAuth::AccessToken;
use Carp;

=head1 NAME

Net::OAuth::Client - OAuth 1.0A Client

=head1 SYNOPSIS

  # Web Server Example (Dancer)

  # This example is simplified for illustrative purposes, see the complete code in /demo

  # Note that client_id is the Consumer Key and client_secret is the Consumer Secret

  use Dancer;
  use Net::OAuth::Client;

  sub client {
  	Net::OAuth::Client->new(
  		config->{client_id},
  		config->{client_secret},
  		site => 'https://www.google.com/',
  		request_token_path => '/accounts/OAuthGetRequestToken?scope=https%3A%2F%2Fwww.google.com%2Fm8%2Ffeeds%2F',
  		authorize_path => '/accounts/OAuthAuthorizeToken',
  		access_token_path => '/accounts/OAuthGetAccessToken',
  		callback => uri_for("/auth/google/callback"),
  		session => \&session,
  	);
  }

  # Send user to authorize with service provider
  get '/auth/google' => sub {
  	redirect client->authorize_url;
  };

  # User has returned with token and verifier appended to the URL.
  get '/auth/google/callback' => sub {

  	# Use the auth code to fetch the access token
  	my $access_token =  client->get_access_token(params->{oauth_token}, params->{oauth_verifier});

  	# Use the access token to fetch a protected resource
  	my $response = $access_token->get('/m8/feeds/contacts/default/full');

  	# Do something with said resource...

  	if ($response->is_success) {
  	  return "Yay, it worked: " . $response->decoded_content;
  	}
  	else {
  	  return "Error: " . $response->status_line;
  	}
  };

  dance;

=head1 DESCRIPTION

Net::OAuth::Client represents an OAuth client or consumer.

WARNING: Net::OAuth::Client is alpha code.  The rest of Net::OAuth is quite
stable but this particular module is new, and is under-documented and under-tested.

  
=head1 METHODS

=over

=item new($client_id, $client_secret, %params)

Create a new Client

=over 

=item * $client_id

AKA Consumer Key - you get this from the service provider when you register your application.

=item * $client_secret

AKA Consumer Secret - you get this from the service provider when you register your application.

=item * $params{site}

=item * $params{request_token_path}

=item * $params{authorize_path}

=item * $params{access_token_path}

=item * $params{callback}

=item * $params{session}

=back

=back

If any of the methods get_request_token, get_access_token or Net::OAuth::AccessToken::request
(returned by authorize_url) are passed a _callback parameter in the %params HASH, then these
methods will use AnyEvent::HTTP as their client and make an asynchronous request. The callback
will be passed the token or HTTP::Response as approptiate.

=cut

sub new {
  my $class = shift;
  my $client_id = shift;
  my $client_secret = shift;
  my %opts = @_;
  $opts{user_agent} ||= LWP::UserAgent->new;
  $opts{id} = $client_id;
  $opts{secret} = $client_secret;
  $opts{is_v1a} = defined $opts{callback};
  my $self = bless \%opts, $class;
  return $self;
}

sub request {
  my $self = shift;
  my $response = $self->user_agent->request(@_);
}

sub make_oauth_http_request {
  my $self = shift;
  my ($method, $oauth_req, $header, $content) = @_;

  my $url;
  
  if ($method eq 'POST') {
  	if ($content) {
  		# XXX use Authorization header
  		croak "Need to use Authorization header for OAUTH POST with content but not supported";
  	} else {
  		$content = $oauth_req->to_post_body;
  		if (!$header) {
  			$header = HTTP::Headers->new;
  		} elsif (ref $header eq 'ARRAY') {
		  	$header = HTTP::Headers->new($header);
  		}
	   	$header->header(
	  		'Content-Type'   => 'application/x-www-form-urlencoded',
	  		'Content-Length' => length($content),
	  	);
  	}
  	$url = $oauth_req->request_url->clone;
  	$url->query(undef);
  } else {
  	$url = $oauth_req->to_url;
  }
  
  return HTTP::Request->new($method => $url, $header, $content);
}

my $loaded_anyevent_http;

sub make_async_oauth_request {
  my $self = shift;
  my ($cb, $method, $oauth_req, $header, $content) = @_;
  
  unless ($loaded_anyevent_http) {
	require AnyEvent::HTTP or croak('Cannot load AnyEvent::HTTP');
    $loaded_anyevent_http = 1;
  }
  
  my $request = $self->make_oauth_http_request($method, $oauth_req, $header, $content);
  
  $header = $request->headers;
  my %headers;
  if ($header) {
	  foreach ($header->header_field_names) {
	  	my $v = $header->header($_);
	  	$headers{$_} = $v;
	  }
  }
  
  AnyEvent::HTTP::http_request $method => $request->uri, headers => \%headers, body => $request->content, sub {
  	my ($body, $hdr) = @_;
  	my $response = HTTP::Response->new( $hdr->{Status}, $hdr->{Reason}, [%$hdr], $body );
  	$response->request($request);
  	$cb->($response);
  };
}

sub _parse_oauth_response {
  my $self = shift;
  my $do_what = shift;
  my $http_res = shift;
  my $msg = "Unable to $do_what: Request for " . $http_res->request->uri . " failed";
  unless ($http_res->is_success) {
    if ($self->debug) { 
      $msg .= "," . $http_res->as_string . " ";      
    }
    elsif (
      $http_res->content_type eq 'application/x-www-form-urlencoded'
      and $http_res->decoded_content =~ /\boauth_problem=(\w+)/
      ) { 
      $msg .= ", reason: " . $1;      
    }
    else {
      $msg .= ": " . $http_res->status_line . " (pass debug=>1 to Net::OAuth::Client->new to dump the entire response)";
    }
    croak $msg;
  }
  my $oauth_res = _parse_url_encoding($http_res->decoded_content);
  foreach my $k (qw/token token_secret/) {
    croak "Unable to $do_what: server response is missing '$k'" unless defined $oauth_res->{$k};
  }
  return $oauth_res;
  
}

sub _parse_url_encoding {
  my $str = shift;
  my @pairs = split '&', $str;
  my %params;
	foreach my $pair (@pairs) {
        my ($k,$v) = split (/=/, $pair);
        if (defined $k and defined $v) {
            $v =~ s/(^"|"$)//g;
            ($k,$v) = map Net::OAuth::Message::decode($_), $k, $v;
            $k =~ s/^oauth_//;
            $params{$k} = $v;
        }
    }
	return \%params;
}

sub get_request_token {
  my $self = shift;
  my %params = @_;
  my $oauth_req = $self->_make_request(
    "request token", 
    request_method => $self->request_token_method,
    request_url => $self->_make_url("request_token"),
    %params
  );
  $oauth_req->sign;
  
  my $cb = sub {
  	my ($http_res) = @_;
  	my $oauth_res = eval {$self->_parse_oauth_response('get a request token', $http_res);};
  	if ($@) {
  		if ($params{_callback}) {
  			return $params{_callback}->({error => $@});
  		} else {
  			die($@);
  		}
  	}
	$self->is_v1a(0) unless defined $oauth_res->{callback_confirmed};
	$params{_callback}->($oauth_res) if ($params{_callback});
	return $oauth_res;
  };
  
  if ($params{_callback}) {
  	$self->make_async_oauth_request($cb, $self->request_token_method, $oauth_req);
  } else {
  	return $cb->($self->request($self->make_oauth_http_request($self->request_token_method, $oauth_req)))
  }
}

sub authorize_url {
  my $self = shift;
  my %params = @_;
  
  # allow user to get request token their own way
  unless (defined $params{token} and defined $params{token_secret}) {
    my $request_token = $self->get_request_token;
    $params{token} = $request_token->{token};
    $params{token_secret} = $request_token->{token_secret};
    $self->{'authorize_url'} = $request_token->{login_url} if $request_token->{login_url};
  }
  if (defined $self->session) {
    $self->session->($params{token} => $params{token_secret});
  }
  my $oauth_req = $self->_make_request(
    'user auth',
    %params
  );
  return $oauth_req->to_url($self->_make_url('authorize'));
}

sub get_access_token {
  my $self = shift;
  my $token = shift;
  my $verifier = shift;
  my %params = @_;
  
  if (defined $self->session) {
    $params{token_secret} = $self->session->($token);
  }

  my $oauth_req = $self->_make_request(
    'access token', 
    request_method => $self->access_token_method,
    request_url => $self->_make_url('access_token'),
    token => $token,
    verifier => $verifier,
    %params
  );
  $oauth_req->sign;

  my $cb = sub {
  	my ($http_res) = @_;
	my $oauth_res = eval {$self->_parse_oauth_response('get an access token', $http_res);};
  	if ($@) {
  		if ($params{_callback}) {
  			return $params{_callback}->({error => $@});
  		} else {
  			die($@);
  		}
  	}
	my $accessToken = Net::OAuth::AccessToken->new(%$oauth_res, client => $self);
	$params{_callback}->($accessToken) if ($params{_callback});
	return $accessToken;
  };
  
  if ($params{_callback}) {
  	$self->make_async_oauth_request($cb, $self->access_token_method, $oauth_req);
  } else {
  	return $cb->($self->request($self->make_oauth_http_request($self->access_token_method, $oauth_req)))
  }

}

sub access_token_url {
  return shift->_make_url('access_token', @_);
}

sub request_token_url {
  return shift->_make_url('request_token', @_);
}

sub access_token_method {
  return shift->{access_token_method} || 'GET';
}

sub request_token_method {
  return shift->{request_token_method} || 'GET';
}

sub _make_request {
  my $self = shift;
  my $type = shift;
  my %params = @_;
  my %defaults = (
    nonce => int( rand( 2**32 ) ),
    timestamp => time,
    consumer_key => $self->id,
    consumer_secret => $self->secret,
    callback => $self->callback,
    signature_method => 'HMAC-SHA1',
    request_method => 'GET',
  );
  $defaults{protocol_version} = Net::OAuth::PROTOCOL_VERSION_1_0A if $self->is_v1a;
  my $req = Net::OAuth->request($type)->new(
    %defaults,
    %params
  );
  return $req;
}

sub _make_url {
  my $self = shift;
  my $thing = shift;
  my $path = $self->{"${thing}_url"} || $self->{"${thing}_path"} || "/oauth/${thing}";
  return $self->site_url($path, @_);
}

sub site_url {
  my $self = shift;
  my $path = shift;
  my %params = @_;
  my $url;
  if (defined $self->{site}) {
    $url = URI->new_abs($path, $self->{site});
  }
  else {
    $url = URI->new($path);
  }
  if (@_) {
    $url->query_form($url->query_form , %params);
  }
  return $url;
}



=head1 LICENSE AND COPYRIGHT

Copyright 2011 Keith Grennan.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut


1;


1;
