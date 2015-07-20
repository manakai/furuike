use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    'foo.txt' => q{abc},
    'foo.html' => q{<p>abc},
    'foo.hoge' => q{z},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, '<p>abc', 'text/html; charset=utf-8'],
      [q</foo.txt>, 'abc', 'text/plain; charset=utf-8'],
      [q</foo.html>, '<p>abc', 'text/html; charset=utf-8'],
      [q</foo.hoge>, 'z', undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), $x->[2];
          is $res->content, $x->[1];
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.>],
      [q</foo.TXT>],
      [q</foo.hog>],
      [q</foo.ja>],
      [q</foo.foo>],
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
} n => 4 * 5 + 5 * 1;

test {
  my $c = shift;
  server ({
    'foo.txt' => q{abc},
    'foo.ja.txt' => q{<p>abc},
    'foo.en.txt' => q{z},
    'foo.en-GB.txt' => q{x},
    'foo.en-Jp.txt' => q{y},
    'foo.fr-Jp.txt' => q{j},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, 'en', 'en', 'z'],
      [q</foo>, 'zh, en', 'en', 'z'],
      [q</foo>, 'fr-jp, fr, ja', 'fr-JP', 'j'],
      [q</foo>, 'en, ja', 'en', 'z'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          is $res->header ('Content-Language'), $x->[2];
          is $res->content, $x->[3];
        } $c, name => [$x->[0], $x->[1]];
      });
    }
    for my $x (
      [q</foo>],
      [q</foo>, 'xx'],
      [q</foo>, 'ja-jp'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          ok $res->header ('Content-Language');
          ok $res->content;
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.en>, 'en', 'z'],
      [q</foo.fr-Jp>, 'fr-JP', 'j'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          is $res->header ('Content-Language'), $x->[1];
          is $res->content, $x->[2];
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.en-gb>],
      [q</foo.es.txt>],
      [q</foo.fr>],
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
} n => 4 * 6 + 3 * 6 + 2 * 6 + 3 * 1;

test {
  my $c = shift;
  server ({
    'foo.txt' => q{abc},
    'foo.txt.gz' => q{ggg},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt.gz>, 'ggg', 'gzip', 'text/plain; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Encoding'), $x->[2];
          is $res->header ('Content-Type'), $x->[3];
          is $res->content, $x->[1];
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.txt>, 'abc', undef, 'text/plain; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Encoding'), $x->[2];
          is $res->header ('Content-Type'), $x->[3];
          is $res->content, $x->[1];
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.gz>],
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
} n => 1 * 6 + 1 * 6 + 1 * 1;

test {
  my $c = shift;
  server ({
    'foo.txt.gz' => q{ggg},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt.gz>, 'ggg', 'gzip', 'text/plain; charset=utf-8'],
      [q</foo.txt>, 'ggg', 'gzip', 'text/plain; charset=utf-8'],
      [q</foo>, 'ggg', 'gzip', 'text/plain; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Encoding'), $x->[2];
          is $res->header ('Content-Type'), $x->[3];
          is $res->content, $x->[1];
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.gz>],
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
} n => 3 * 6 + 1 * 1;

test {
  my $c = shift;
  server ({
    'foo.txt.u8' => q{ggg},
    'foo.txt.sjis' => q{hhh},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt>, 'ggg', 'text/plain; charset=utf-8'],
      [q</foo>, 'ggg', 'text/plain; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), $x->[2];
          is $res->content, $x->[1];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 5;

test {
  my $c = shift;
  server ({
    'foo.js.js' => q{ggg},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.js>, 'js', 'text/javascript; charset=utf-8'],
      [q</foo.js.js>, 'js', 'text/javascript; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Language'), $x->[1];
          is $res->header ('Content-Type'), $x->[2];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 5;

test {
  my $c = shift;
  server ({
    'foo.js' => q{ggg},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.js>, undef, 'text/javascript; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Language'), $x->[1];
          is $res->header ('Content-Type'), $x->[2];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 1 * 5;

test {
  my $c = shift;
  server ({
    'foo.txt.jis' => q{ggg},
    'bar.xhtml.jis' => q{xyz},
    'baz.json.jis' => q{zyz},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo.txt.jis>, 'ggg', 'text/plain; charset=iso-2022-jp'],
      [q</foo.txt>, 'ggg', 'text/plain; charset=iso-2022-jp'],
      [q</foo>, 'ggg', 'text/plain; charset=iso-2022-jp'],
      [q</bar.xhtml.jis>, 'xyz', 'application/xhtml+xml; charset=iso-2022-jp'],
      [q</bar.xhtml>, 'xyz', 'application/xhtml+xml; charset=iso-2022-jp'],
      [q</bar>, 'xyz', 'application/xhtml+xml; charset=iso-2022-jp'],
      [q</baz.json.jis>, 'zyz', undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Type'), $x->[2];
          is $res->content, $x->[1];
        } $c, name => $x->[0];
      });
    }
    for my $x (
      [q</foo.jis>],
      [q</baz.json>],
      [q</baz>],
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
} n => 7 * 5 + 3 * 1;

test {
  my $c = shift;
  server ({
    'foo.html/hoge' => q{<p>abc},
    'bar.html' => \q{foo.html/hoge},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>],
      [q</bar>],
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
} n => 2 * 1, name => 'not file';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
