use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    'hoge/index.html' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge/>],
      [q</hoge/?foo>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), q{text/html; charset=utf-8};
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->content, q{<p>foo};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 5 * 2, name => 'directory';

test {
  my $c = shift;
  server ({
    'hoge/index.txt' => q{<p>foo},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge/>],
      [q</hoge/?foo>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->content, q{<p>foo};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 5 * 2, name => 'directory';

test {
  my $c = shift;
  server ({
    'hoge/index.ja.html' => q{Japanese},
    'hoge/index.en.html' => q{English},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge/>, 'ja', 'Japanese', 'ja'],
      [q</hoge/>, 'en', 'English', 'en'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), q{text/html; charset=utf-8};
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Language'), $x->[3];
          is $res->content, $x->[2];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 6 * 2, name => 'directory';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{DirectoryIndex foo index},
    'hoge/foo.ja.html' => q{Japanese},
    'hoge/index.en.html' => q{English},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge/>, 'ja', 'Japanese', 'ja'],
      [q</hoge/>, 'en', 'Japanese', 'ja'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), q{text/html; charset=utf-8};
          is $res->header ('X-Content-Type-Options'), q{nosniff};
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Language'), $x->[3];
          is $res->header ('Vary'), 'Accept-Language';
          is $res->content, $x->[2];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 8 * 2, name => 'DirectoryIndex';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{DirectoryIndex index.en foo},
    'hoge/foo.ja.html' => q{Japanese},
    'hoge/index.en.html' => q{English},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge/>, 'ja', 'English', 'en'],
      [q</hoge/>, 'en', 'English', 'en'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), q{text/html; charset=utf-8};
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          is $res->header ('Content-Language'), $x->[3];
          is $res->content, $x->[2];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 6 * 2, name => 'DirectoryIndex';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
