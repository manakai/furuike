use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Redirect 301 /foo /hoge/fuga
      Redirect 302 /bar.html  http://foo/hoge/
      Redirect 303 /dir/zab.txt xyz
      Redirect 307 /zzz /z/z/
      Redirect 308 /z2 /Z2
      Redirect permanent /L1 http://l1/
      Redirect temp /L2 http://l2/
      Redirect seeother /L3/a /a
      Redirect 301 /L3 /b
      Redirect 302 /L4/a /a
      Redirect 302 /L4 /b
    },
    'dir/abc' => q{},
    'zzz' => q{},
    'z2/abc' => q{},
    'L1' => \q{zzz},
    'L2' => \q{z2},
    'L4' => \q{z2},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, 301, 'http://HOST/hoge/fuga'],
      [q</foo.txt>, 404, undef],
      [q</foobar>, 404, undef],
      [q</foo/>, 404, undef],
      [q</foo/bar>, 404, undef],
      [q</bar>, 404, undef],
      [q</bar.html>, 302, 'http://foo/hoge/'],
      [q</bar.html.gz>, 404, undef],
      [q</bar.html/>, 404, undef],
      [q</bar.html2>, 404, undef],
      [q</bar.html/aaa>, 404, undef],
      [q</dir/zab.txt>, 303, 'http://HOST/dir/xyz', 'subdirectory'],
      [q</zzz>, 307, 'http://HOST/z/z/', 'file found but ignored'],
      [q</zzz/>, 404, undef],
      [q</zzz/aaa>, 404, undef],
      [q</z2>, 308, 'http://HOST/Z2', 'directory found but ignored'],
      [q</z2/>, 200, undef],
      [q</z2/abc>, 200, undef],
      [q</L1>, 301, q<http://l1/>],
      [q</L1/>, 404, undef],
      [q</L1/a>, 404, undef],
      [q</L2>, 302, q<http://l2/>],
      [q</L2/>, 404, undef],
      [q</L2/a>, 404, undef],
      [q</L3>, 301, q<http://HOST/b>, 'virtual directory, file path'],
      [q</L3/>, 404, undef, 'virtual file path'],
      [q</L3/a>, 303, q<http://HOST/a>, 'virtual file'],
      [q</L3/a/>, 404, undef],
      [q</L3/a/z>, 404, undef],
      [q</L3/a/z/c>, 404, undef],
      [q</L4>, 302, q<http://HOST/b>, 'virtual dir, file path / symlink'],
      [q</L4/>, 404, undef, 'virtual file path / symlink'],
      [q</L4/a>, 302, q<http://HOST/a>, 'virtual file / symlink'],
      [q</L4/a/>, 404, undef],
      [q</L4/a/z>, 404, undef],
      [q</L4/a/z/c>, 404, undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 36 * 2, name => 'Redirect real redirect';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Redirect 403 /bar
      Redirect 404 /foo
      Redirect 410 /a1/bar
      Redirect gone /a2
      Redirect 503 /hoge/fuga
      Redirect 500 /a3/
    },
    'a1/aaa' => q{},
    'a2' => \q{a1},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, 404, undef],
      [q</bar>, 403, undef],
      [q</hoge>, 301, q<http://HOST/hoge/>],
      [q</hoge/>, 404, undef],
      [q</hoge/fuga>, 503, undef],
      [q</hoge/fuga/>, 503, undef],
      [q</hoge/fuga/abc>, 503, undef],
      [q</a1>, 301, q<http://HOST/a1/>],
      [q</a1/>, 200, undef],
      [q</a1/bar>, 410, undef],
      [q</a1/bar/>, 410, undef],
      [q</a1/bar/a>, 410, undef],
      [q</a2>, 410, undef],
      [q</a2/>, 410, undef],
      [q</a2/a>, 410, undef],
      [q</a3>, 500, undef],
      [q</a3/>, 500, undef],
      [q</a3/a>, 500, undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
          if (defined $x->[2] or $x->[1] == 200) {
            like $res->content, qr{<!DOCTYPE };
          } else {
            like $res->content, qr{^$x->[1]};
          }
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 18 * 3, name => 'Redirect error response';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Redirect 403 /bar
      Redirect 404 /foo
      Redirect 410 /a1/bar
      Redirect gone /a2
      Redirect 503 /hoge/fuga
      Redirect 500 /a3/
      ErrorDocument 403 /403.txt
      ErrorDocument 404 /404.txt
      ErrorDocument 410 /410.txt
      ErrorDocument 503 /503.txt
      ErrorDocument 500 /500.txt
    },
    '403.txt' => '[[403]]',
    '404.txt' => '[[404]]',
    '410.txt' => '[[410]]',
    '500.txt' => '[[500]]',
    '503.txt' => '[[503]]',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, 404, undef],
      [q</bar>, 403, undef],
      [q</hoge/>, 404, undef],
      [q</hoge/fuga>, 503, undef],
      [q</a1/bar>, 410, undef],
      [q</a1/bar/>, 410, undef],
      [q</a1/bar/a>, 410, undef],
      [q</a2>, 410, undef],
      [q</a2/>, 410, undef],
      [q</a2/a>, 410, undef],
      [q</a3/>, 500, undef],
      [q</a3/a>, 500, undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
          like $res->content, qr{^\[\[$x->[1]\]\]$};
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 12 * 3, name => 'Redirect error response, ErrorDocument';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Redirect /foo/bar/baz http://hoge/
      Redirect /foo/baz/baz http://hoge/
    },
    '/foo/bar' => q{abc},
    '/foo/baz' => \q{abc},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo/bar>, 200, undef],
      [q</foo/bar/>, 404, undef],
      [q</foo/bar/baz>, 302, q<http://hoge/>],
      [q</foo/baz>, 301, q<http://HOST/foo/baz/>],
      [q</foo/baz/>, 404, undef],
      [q</foo/baz/baz>, 302, q<http://hoge/>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 6 * 2, name => 'Redirect confliction';

test {
  my $c = shift;
  server ({
    'foo/.htaccess' => q{
      Redirect /abc http://hoge/abc
      Redirect /foo/bar http://hoge/bar
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</abc>, 404, undef],
      [q</foo>, 301, q<http://HOST/foo/>],
      [q</foo/>, 200, undef],
      [q</foo/bar>, 302, q<http://hoge/bar>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'Redirect subdirectory';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Redirect /abc http://hoge/abc
      <IfModule Furuike>
        FuruikeRedirectTop http://hoge/
        FuruikeRedirectTop http://hoge.foo.bar/
      </IfModule>
      Redirect /foo/bar/baz http://hoge/fuga
      Redirect /zzz http://hoge.foo.bar/
      Redirect /zz2 https://hoge.foo.bar/
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo/bar/baz>, 302, q<http://HOST/fuga>],
      [q</abc>, 302, q<http://hoge/abc>],
      [q</zzz>, 302, q<http://HOST/>],
      [q</zz2>, 302, q<https://hoge.foo.bar/>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'FuruikeRedirectTop';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      RedirectMatch 301 /foo/.* http://hoge/
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, 301, q<http://hoge/>],
      [q</foo/>, 301, q<http://hoge/>],
      [q</foo/fuga>, 301, q<http://hoge/fuga>],
      [q</foo/fuga/bar>, 301, q<http://hoge/fuga/bar>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4 * 2, name => 'RedirectMatch';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      RedirectMatch 302 /foo/$ http://hoge/
      RedirectMatch 303 /bar$ http://hoge/
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</foo>, 301, q<http://HOST/foo/>],
      [q</foo/>, 302, q<http://hoge/>],
      [q</foo/fuga>, 404, undef],
      [q</foo/fuga/bar>, 404, undef],
      [q</bar>, 303, q<http://hoge/>],
      [q</bar/>, 404, undef],
      [q</bar/fuga>, 404, undef],
      [q</bar/fuga/bar>, 404, undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 8 * 2, name => 'RedirectMatch';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Redirect 301 /hoge/ https://hoge/fuga/
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</hoge>, 301, q<https://hoge/fuga/>],
      [q</hoge/>, 301, q<https://hoge/fuga/>],
      [q</hoge/abc>, 301, q<https://hoge/fuga/abc>],
      [q</hoge/a/b/>, 301, q<https://hoge/fuga/a/b/>],
      [q</hoge/a/b/z>, 301, q<https://hoge/fuga/a/b/z>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, $x->[1];
          $x->[2] =~ s{^http://HOST}{'http://'.$server->get_host}e
              if defined $x->[2];
          is $res->header ('Location'), $x->[2];
        } $c, name => [$x->[0], $x->[3]];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 5 * 2, name => 'Redirect descendants';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
