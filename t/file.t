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
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
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
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          is $res->content, q{404 Directory not found};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 5 * 4 + 6 * 3;

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
          is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          is $res->header ('X-Content-Type-Options'), 'nosniff';
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
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          like $res->content, qr{^404 (?:Directory not found|Bad path)$};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 3 + 4 * 3;

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
    '.htaccess' => '#foo',
    'abbb/.htaccess' => '#foo',
    '.git/foo' => 'a',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt>],
      [q</ab/cd.txt>],
      [q</xyz>, 301],
      [q</xyz/>],
      [q</xyz/abc>],
      [q</.htaccess>, 404],
      [q</abbb/.htaccess>, 404],
      [q</.git>, 404],
      [q</.git/>, 404],
      [q</.git/foo>, 404],
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
} n => 4 * 2 + 6 * 1, name => 'unreadable file';

test {
  my $c = shift;
  server ({
    'foo.txt' => qq{abc\xFE\x80\x12\x90\x00},
    'foo.html' => qq{abc\xFE\x80\x12\x90\x00},
    'bar/foo.js' => qq{abc\xFE\x80\x12\x90\x00},
    'bar/foo.png' => qq{abc\xFE\x80\x12\x90\x00},
    'bar/foo.json' => qq{abc\xFE\x80\x12\x90\x00},
    'bar/foo' => qq{abc\xFE\x80\x12\x90\x00},
    '~bar/foo' => qq{abc\xFE\x80\x12\x90\x00},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      ['/foo.txt', 'text/plain; charset=utf-8'],
      ['/foo.html', 'text/html; charset=utf-8'],
      ['/bar/foo.js', 'text/javascript; charset=utf-8'],
      ['/bar/foo.js?hoge.html', 'text/javascript; charset=utf-8'],
      ['/bar/foo.png', 'image/png'],
      ['/bar/foo.json', 'application/json; charset=utf-8'],
      ['/bar/foo', undef],
      ['/~bar/foo', undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), $x->[1];
          is $res->content, qq{abc\xFE\x80\x12\x90\x00};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 8;

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
