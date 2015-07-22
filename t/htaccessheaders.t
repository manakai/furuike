use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      AddType text/html .foo bar2
    },
    'aa.foo' => q{aa},
    'abc.bar2' => q{bb},
    'b/.htaccess' => q{
      AddType image/PNG foo
    },
    'b/aa.foo' => q{aa},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</aa>, 'text/html; charset=utf-8'],
      [q</aa.foo>, 'text/html; charset=utf-8'],
      [q</abc>, 'text/html; charset=utf-8'],
      [q</abc.bar2>, 'text/html; charset=utf-8'],
      [q</b/aa>, 'image/png'],
      [q</b/aa.foo>, 'image/png'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), $x->[1];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 6 * 2, name => 'AddType';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      AddCharset ISO-8859-1 .iso
    },
    'aa.txt.iso' => q{aa},
    'aa.iso' => q{aa},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</aa.txt>, 'text/plain; charset=iso-8859-1'],
      [q</aa.txt.iso>, 'text/plain; charset=iso-8859-1'],
      [q</aa.iso>, undef],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), $x->[1];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 2, name => 'AddCharset';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      AddEncoding compress .Z
    },
    'aa.Z' => q{aa},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</aa>, 'compress'],
      [q</aa.Z>, 'compress'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Encoding'), $x->[1];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 2, name => 'AddEncoding';

test {
  my $c = shift;
  server ({
    'foo/.htaccess' => q{
      AddDefaultCharset ISO-8859-3
      AddType text/cache-manifest .manifest
    },
    'aa.txt' => q{aa},
    'foo/aa.txt' => q{aa},
    'foo/bar/index.html' => q{aa},
    'foo/x.css' => q{aa},
    'foo/x.js' => q{aa},
    'foo/x.png' => q{aa},
    'foo/x.xml' => q{aa},
    'foo/x.xhtml' => q{aa},
    'foo/x.svg' => q{aa},
    'foo/x.json' => q{aa},
    'foo/x.manifest' => q{aa},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</aa.txt>, 'text/plain; charset=utf-8'],
      [q</404>, 'text/plain; charset=utf-8'],
      [q</foo>, 'text/html; charset=utf-8'],
      [q</foo/>, 'text/html; charset=utf-8'],
      [q</foo/aa>, 'text/plain; charset=iso-8859-3'],
      [q</foo/aa.txt>, 'text/plain; charset=iso-8859-3'],
      [q</foo/404>, 'text/plain; charset=utf-8'],
      [q</foo/bar/index.html>, 'text/html; charset=iso-8859-3'],
      [q</foo/x.css>, 'text/css; charset=iso-8859-3'],
      [q</foo/x.js>, 'text/javascript; charset=iso-8859-3'],
      [q</foo/x.xml>, 'text/xml; charset=iso-8859-3'],
      [q</foo/x.xhtml>, 'application/xhtml+xml; charset=iso-8859-3'],
      [q</foo/x.svg>, 'image/svg+xml; charset=iso-8859-3'],
      [q</foo/x.png>, 'image/png'],
      [q</foo/x.manifest>, 'text/cache-manifest; charset=utf-8'],
      [q</foo/x.json>, 'application/json; charset=utf-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->header ('Content-Type'), $x->[1];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 16 * 1, name => 'AddDefaultCharset';

test {
  my $c = shift;
  server ({
    'README' => q{aa},
    'README.html' => q{bb},
    'LICENSE' => q{b},
    'foo/.htaccess' => q{
      ReadmeName bar
    },
    'foo/README' => q{aa},
    'foo/bar' => q{bb},
    'abc/.htaccess' => q{
      IndexOptions +charset=ISO-8859-8
    },
    'abc/README' => q{aa},
    'abc/README.html' => q{aa},
    'abc/def/README.html' => q{aa},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</README>, 'text/plain; charset=utf-8'],
      [q</LICENSE>, 'text/plain; charset=utf-8'],
      [q</README.html>, 'text/html; charset=utf-8'],
      [q</foo/README>, undef],
      [q</foo/bar>, 'text/plain; charset=utf-8'],
      [q</abc/README>, 'text/plain; charset=iso-8859-8'],
      [q</abc/README.html>, 'text/html; charset=iso-8859-8'],
      [q</abc/def/README>, 'text/html; charset=iso-8859-8'],
      [q</abc/def/README.html>, 'text/html; charset=iso-8859-8'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          is $res->header ('Content-Type'), $x->[1];
          is $res->header ('X-Content-Type-Options'), defined $x->[1] ? 'nosniff' : undef;
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 9 * 3, name => 'README and LICENSE';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{
      Header add X-Test ""
      Header add X-Test2 "fo\"bar\"o\\\\"
      <Files o>
        Header add X-Test3 "aa"
      </Files>
      <Files "o">
        Header add X-Test4 "bb"
      </Files>
      <Files ~ "^(abc|de)">
        Header add X-Test4 "cc"
      </Files>
      <Files ~ "p">
        Header add X-Test4 "dd"
      </Files>
    },
    'hoge' => q{},
    'foo/bar' => q{},
    'o' => q{},
    'abcfoo' => q{},
    'de-aa' => q{},
    'apa' => q{},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>, '', 'fo"bar"o\\', undef, undef],
      [q</aa>, undef, undef, undef, undef],
      [q</foo>, undef, undef, undef, undef],
      [q</foo/>, '', 'fo"bar"o\\', undef, undef],
      [q</foo/bar>, '', 'fo"bar"o\\', undef, undef],
      [q</o>, '', 'fo"bar"o\\', 'aa', 'bb'],
      [q</abcfoo>, '', 'fo"bar"o\\', undef, 'cc'],
      [q</de-aa>, '', 'fo"bar"o\\', undef, 'cc'],
      [q</apa>, '', 'fo"bar"o\\', undef, 'dd'],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->header ('X-Test'), $x->[1];
          is $res->header ('X-Test2'), $x->[2];
          is $res->header ('X-Test3'), $x->[3];
          is $res->header ('X-Test4'), $x->[4];
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 18 * 2, name => 'Header';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
