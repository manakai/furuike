use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    '.htaccess' => q{aa},
    'foo' => q{aa},
    'hoge/index.html' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
      [q</.htaccess>],
      [q</foo>],
      [q</foo2>],
      [q</hoge/>],
      [q</hoge/index>],
      [q</hoge/index.html>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 500;
          is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          is $res->content, q{500 Server error};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 7, name => 'root .htaccess parse error';

test {
  my $c = shift;
  server ({
    'hoge/.htaccess' => q{aa},
    'foo' => q{aa},
    'hoge/index.html' => q{<p>foo},
    'hoge/fuga/index.html' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge/>],
      [q</hoge/index>],
      [q</hoge/index.html>],
      [q</hoge/fuga/index.html>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 500;
          is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          is $res->content, q{500 Server error};
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</>],
      [q</foo>],
      [q</foo2>, 404],
      [q</hoge>, 301],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1] || 200;
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 3 + 1 * 4, name => 'non-root .htaccess parse error';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
##comment
<IfModule dummy>
abc
</IfModule>
    },
    'foo' => q{aa},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
      [q</foo>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1] || 200;
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 1 * 2, name => '.htaccess ignored';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
