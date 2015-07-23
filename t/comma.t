use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    'hogendex.html' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</,imglist>],
      [q</LIST,imglist>],
      [q</bar,imglist>],
      [q</,imglist-detail>],
      [q</LIST,imglist-detail>],
      [q</foo,imglist-detail>],
      [q</foo,imglist-detail?abc>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 301;
          my $host = $server->get_host;
          is $res->header ('Location'), qq<http://$host/LIST>;
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 14, name => 'LIST redirects';

test {
  my $c = shift;
  server ({
    'hogendex.html' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</abc/,imglist>],
      [q</abc/LIST,imglist>],
      [q</abc/bar,imglist>],
      [q</abc/,imglist-detail>],
      [q</abc/LIST,imglist-detail>],
      [q</abc/foo,imglist-detail>],
      [q</abc/foo,imglist-detail?abc>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 301;
          my $host = $server->get_host;
          is $res->header ('Location'), qq<http://$host/abc/LIST>;
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 14, name => 'LIST redirects';

test {
  my $c = shift;
  server ({
    'hogendex.html' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</,comma>],
      [q</,tools>],
      [q</,m3u>],
      [q</hoge,tools>],
      [q</hoge,text>],
      [q</hoge,cvslog>],
      [q</hoge,validate>],
      [q</hoge,foo,bar>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 8, name => 'not found';

test {
  my $c = shift;
  server ({
    'foo,bar' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo,bar>, 404],
      [q</foo,bar,baz>, 404],
      [q</foo%2Cbar>, 404],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3, name => 'comma';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
