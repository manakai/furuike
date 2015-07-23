use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

for my $path (
  q</notfoind>,
  q</not/found>,
  q<//hoge>,
  q<///a>,
  q</!-$>,
  q</%%>,
  q</ho//>,
  q</foo.txt>,
  q</foo.html>,
  q</favicon.ico>,
  q</foo%2Fbar>,
  q</foo/LIST>,
  q</foo/bar/LIST>,
) {
  test {
    my $c = shift;
    server->then (sub {
      my $server = $_[0];
      return GET ($server, $path)->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
          like $res->content, qr{^404 (File not found|Directory not found|Bad path)$};
        } $c;
      })->then (sub {
        return $server->stop;
      })->then (sub { done $c; undef $c });
    });
  } n => 3, name => $path;
}

for my $path (
  q</ >,
  q</foo bar>,
) {
  test {
    my $c = shift;
    server->then (sub {
      my $server = $_[0];
      return GET ($server, $path)->then (sub {
        my $res = $_[0];
        test {
          like $res->code, qr{^40[04]$};
        } $c;
      })->then (sub {
        return $server->stop;
      })->then (sub { done $c; undef $c });
    });
  } n => 1, name => $path;
}

test {
  my $c = shift;
  server ({
    'error/404.txt' => 'aaa<p>',
    '.htaccess' => 'ErrorDocument 404 /error/404',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>],
      [q</hoge.html>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          is $res->content, 'aaa<p>';
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 2, name => 'ErrorDocument';

test {
  my $c = shift;
  server ({
    'error/404.ja.html' => 'JA',
    'error/404.en.html' => 'EN',
    '.htaccess' => 'ErrorDocument 404 /error/404',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>, 'ja', 'ja', 'JA'],
      [q</hoge.html>, 'en', 'en', 'EN'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), 'text/html; charset=utf-8';
          is $res->header ('Content-Language'), $x->[2];
          is $res->content, $x->[3];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'ErrorDocument';

test {
  my $c = shift;
  server ({
    'error/404.ja.html' => 'JA',
    'error/404.en.html' => 'EN',
    '.htaccess' => 'ErrorDocument 404 /error/404.ja.html',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>, 'ja', 'ja', 'JA'],
      [q</hoge.html>, 'en', 'ja', 'JA'],
      [q</hoge/foo/>, 'ja', 'ja', 'JA'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), 'text/html; charset=utf-8';
          is $res->header ('Content-Language'), $x->[2];
          is $res->header ('Vary'), 'Accept-Language';
          is $res->content, $x->[3];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 5 * 3, name => 'ErrorDocument';

test {
  my $c = shift;
  server ({
    '.htaccess' => 'ErrorDocument 404 /error/404.ja.html',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>, 'ja', undef, '404 File not found'],
      [q</hoge/fu>, 'ja', undef, '404 Directory not found'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          is $res->header ('Content-Language'), $x->[2];
          is $res->content, $x->[3];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'ErrorDocument not found';

test {
  my $c = shift;
  server ({
    '.htaccess' => 'ErrorDocument 404 /404',
    '404/hoge' => '',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>, 'ja', undef, '404 File not found'],
      [q</hoge/fu>, 'ja', undef, '404 Directory not found'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0], langs => $x->[1]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), 'text/plain; charset=utf-8';
          is $res->header ('Content-Language'), $x->[2];
          is $res->content, $x->[3];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'ErrorDocument not file';

test {
  my $c = shift;
  server ({
    'error/404.txt' => 'aaa<p>',
    '.htaccess' => '
      AddDefaultCharset euc-jp
    ',
    'foo/.htaccess' => '
      ErrorDocument 404 /error/404
      AddDefaultCharset iso-2022-jp
    ',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo/hoge>],
      [q</foo/hoge.html>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 404;
          is $res->header ('Content-Type'), 'text/plain; charset=euc-jp';
          is $res->header ('X-Content-Type-Options'), 'nosniff';
          is $res->content, 'aaa<p>';
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'ErrorDocument';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
