use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/lib');
use Tests;

Test {
  my $current = shift;
  return $current->create_session (1)->then (sub {
    return $current->post (['login'], {
      server => 'oauth1server',
      callback_url => 'http://haoa/',
    }, session => 1);
  })->then (sub {
    return $current->post (['cb'], {}, session => 1);
  })->then (sub { test { ok 0 } $current->c }, sub {
    my $result = $_[0];
    test {
      is $result->{status}, 400;
      is $result->{json}->{reason}, 'Bad |state|';
      ok ! $result->{json}->{need_reload};
    } $current->c;
  });
} n => 3, name => '/login then /cb';

Test {
  my $current = shift;
  my $cb_url = 'http://haoa/' . rand;
  return $current->create_session (1)->then (sub {
    return $current->post (['login'], {
      server => 'oauth1server',
      callback_url => $cb_url,
    }, session => 1);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
    } $current->c;
    my $url = Web::URL->parse_string ($result->{json}->{authorization_url});
    my $con = $current->client_for ($url);
    return $con->request (url => $url, method => 'POST'); # user accepted!
  })->then (sub {
    my $result = $_[0];
    return test {
      is $result->status, 302;
      my $location = $result->header ('Location');
      my ($base, $query) = split /\?/, $location, 2;
      is $base, $cb_url;
      return $current->post ("/cb?$query", {}, session => 1);
    } $current->c;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      is $result->{json}->{app_data}, undef;
      ok ! $result->{json}->{need_reload};
    } $current->c;
    return $current->post (['info'], {with_linked => 'id'}, session => 1);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $links = $result->{json}->{links};
      ok grep { $_->{service_name} eq 'oauth1server' } values %$links;
    } $current->c;
  });
} n => 8, name => '/login then auth then /cb - new account, oauth1';

Test {
  my $current = shift;
  my $cb_url = 'http://haoa/' . rand;
  my $account_id;
  my $x_account_id = int rand 1000000;
  return $current->create_session (1)->then (sub {
    return $current->post (['login'], {
      server => 'oauth2server',
      callback_url => $cb_url,
    }, session => 1);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
    } $current->c;
    my $url = Web::URL->parse_string ($result->{json}->{authorization_url});
    my $con = $current->client_for ($url);
    return $con->request (url => $url, method => 'POST', params => {
      account_id => $x_account_id,
    }); # user accepted!
  })->then (sub {
    my $result = $_[0];
    return test {
      is $result->status, 302;
      my $location = $result->header ('Location');
      my ($base, $query) = split /\?/, $location, 2;
      is $base, $cb_url;
      return $current->post ("/cb?$query", {}, session => 1);
    } $current->c;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      is $result->{json}->{app_data}, undef;
      ok ! $result->{json}->{need_reload};
    } $current->c;
    return $current->post (['info'], {with_linked => 'id'}, session => 1);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $links = $result->{json}->{links};
      ok grep { $_->{service_name} eq 'oauth2server' } values %$links;
      ok $account_id = $result->{json}->{account_id}, 'new account';
    } $current->c;
  })->then (sub {
    return $current->create_session (2);
  })->then (sub {
    return $current->post (['login'], {
      server => 'oauth2server',
      callback_url => $cb_url,
    }, session => 2);
  })->then (sub {
    my $result = $_[0];
    my $url = Web::URL->parse_string ($result->{json}->{authorization_url});
    my $con = $current->client_for ($url);
    return $con->request (url => $url, method => 'POST', params => {
      account_id => $x_account_id,
    }); # user accepted!
  })->then (sub {
    my $result = $_[0];
    my $location = $result->header ('Location');
    my ($base, $query) = split /\?/, $location, 2;
    return $current->post ("/cb?$query", {}, session => 2);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      is $result->{json}->{app_data}, undef;
      ok ! $result->{json}->{need_reload};
    } $current->c;
    return $current->post (['info'], {with_linked => 'id'}, session => 2);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
      my $links = $result->{json}->{links};
      my $ls = [grep { $_->{service_name} eq 'oauth2server' } values %$links];
      is $ls->[0]->{id}, $x_account_id;
      is $result->{json}->{account_id}, $account_id, 'existing account';
    } $current->c;
  });
} n => 15, name => '/login then auth then /cb - oauth2';

Test {
  my $current = shift;
  my $cb_url = 'http://haoa/' . rand;
  my $account_id;
  my $x_account_id = int rand 1000000;
  return $current->create_session (1)->then (sub {
    return $current->post (['login'], {
      server => 'oauth2server_wrapped',
      callback_url => $cb_url,
    }, session => 1);
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->{status}, 200;
    } $current->c;
    my $url = Web::URL->parse_string ($result->{json}->{authorization_url});
    test {
      $url->query =~ m{redirect_uri=([^&]+)};
      my $u = percent_decode_c $1;
      is $u, qq{http://cb.wrapper.test/wrapper/@{[percent_encode_c $cb_url]}?url=@{[percent_encode_c $cb_url]}&test=1};
    } $current->c;
  });
} n => 2, name => 'wrapped /cb URL';

RUN;

=head1 LICENSE

Copyright 2015-2021 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
