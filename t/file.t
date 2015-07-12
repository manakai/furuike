use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    'foo.txt' => q{abc
あいうえお
},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt>, 'path only'],
      [q</foo.txt?avaa>, 'path with query'],
      [q</bar.txt/../foo.txt>],
      [q</bar.txt/../../foo.txt>],
      #[q<//foo.txt>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          #is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          is $res->content, q{abc
あいうえお
};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    for my $x (
      [q</foo.txt/>],
      [q</foo.txt//>],
      [q</foo.txt/hoge>],
      [q</foo.txt//hoge>],
      [q</foo.txt/.>],
      [q</foo.txt/.hoge>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->content, q{404 Directory not found};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2 + 6 * 2;

test {
  my $c = shift;
  server ({
    'abc/def/foo.txt' => q{abc
あいうえお
},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</abc/def/foo.txt>],
      [q</abc/def/foo%2Etxt>],
      [q</%61bc/def/foo.txt>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          #is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          is $res->content, q{abc
あいうえお
};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    for my $x (
      [q</abc/def/foo.txt/>],
      [q</abc//def/foo.txt>],
      [q</abc/DEF/foo.txt>],
      [q</abc/def%2Ffoo.txt>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          like $res->content, qr{^404 (?:Directory not found|Bad path)$};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 2 + 4 * 2;

test {
  my $c = shift;
  server ({
    'foo.txt' => \q{abc/def/foo.txt},
    'abc/def/foo.txt' => q{abc
あいうえお
},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt>],
      [q</foo.txt/abc>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          like $res->content, qr{^404 (?:File not found|Directory not found|Bad path)$};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 2, name => 'symlink file';

test {
  my $c = shift;
  server ({
    'aaa/foo.txt' => \q{abc/def/foo.txt},
    'abc/def/foo.txt' => q{abc
あいうえお
},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</aaa/foo.txt>],
      [q</aaa/foo.txt/abc>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          like $res->content, qr{^404 (?:File not found|Directory not found|Bad path)$};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 2, name => 'symlink file';

test {
  my $c = shift;
  server ({
    'aaa' => \q{abc/def},
    'abc/def/foo.txt' => q{abc
あいうえお
},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</aaa>],
      [q</aaa/>],
      [q</aaa/foo.txt>],
      [q</aaa//foo.txt>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          like $res->content, qr{^404 (?:File not found|Directory not found|Bad path)$};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'symlink directory file';

test {
  my $c = shift;
  server ({
    'foo.txt' => {unreadable => 1},
    'ab/cd.txt' => {unreadable => 1},
    'xyz' => {unreadable => 1, directory => 1},
    '.htaccess' => 'foo',
    'abbb/.htaccess' => 'foo',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt>],
      [q</ab/cd.txt>],
      [q</xyz>, 301],
      [q</xyz/>],
      [q</xyz/abc>, 404],
      [q</.htaccess>, 404],
      [q</abbb/.htaccess>, 404],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          if ($x->[1]) {
            is $res->code, $x->[1];
          } else {
            is $res->code, 500;
            like $res->content, qr{^500 Server error$};
          }
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 2 + 4 * 1, name => 'unreadable file';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
