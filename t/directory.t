use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
      [q</?ab>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{</ul>};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 2, name => 'document root, empty';

test {
  my $c = shift;
  server ({
    hoge => {directory => 1},
    'hoge-5.1./foo' => '',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>, 301, q<http://> . $server->get_host . q</hoge/>],
      [q</hoge/>],
      [q</hoge/?ab>],
      [q</hoge-5.1./>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          if ($x->[1] and $x->[1] == 301) {
            is $res->code, 301;
            is $res->header ('Location'), $x->[2];
          } else {
            is $res->code, 200;
            like $res->content, qr{</ul>};
          }
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'directory';

test {
  my $c = shift;
  server ({
    'foo/bar/baz.txt' => '',
    'foo/bar/Fuga/a' => '',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo/bar/>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{baz.txt};
          like $res->content, qr{Fuga};
          like $res->content, qr{rel=top};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4, name => 'directory';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
