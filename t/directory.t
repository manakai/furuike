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
          is $res->header ('Content-Type'), q{text/html; charset=utf-8};
          like $res->header ('Last-Modified'), qr{GMT};
          unlike $res->header ('Last-Modified'), qr{ 1970 };
          like $res->content, qr{</ul>};
        } $c, name => $x->[1] // $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 5, name => 'document root, empty';

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
            is $res->header ('Last-Modified'), undef;
          } else {
            is $res->code, 200;
            is $res->header ('Content-Type'), q{text/html; charset=utf-8};
            like $res->header ('Last-Modified'), qr{GMT};
            unlike $res->header ('Last-Modified'), qr{ 1970 };
            like $res->content, qr{</ul>};
          }
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3 * 1 + 5 * 3, name => 'directory';

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

test {
  my $c = shift;
  server ({
    '.htpasswd' => '',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          unlike $res->content, qr{.htpasswd};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2, name => 'hidden files';

test {
  my $c = shift;
  server ({
    'foo.bar.ja.html.gz' => '',
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{\Q<a href="foo.bar">foo.bar</a>.<a href="foo.bar.ja">ja</a>.<a href="foo.bar.ja.html">html</a>.<a href="foo.bar.ja.html.gz">gz</a>\E};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2, name => 'file extensions';

test {
  my $c = shift;
  server ({
    '.htaccess' => q{IndexStyleSheet "hoge/fuga%a&"},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<link rel=stylesheet href="hoge/fuga%a&amp;">};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2, name => 'IndexStyleSheet';

test {
  my $c = shift;
  server ({
    'README' => q{<p>aa'&},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{\Q<pre>&lt;p&gt;aa'&amp;</pre>\E};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2, name => 'default README';

test {
  my $c = shift;
  server ({
    'README' => q{<p>aa'&},
    'LICENSE' => q{<X>aa'&},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{\Q<pre>&lt;p&gt;aa'&amp;</pre>\E};
          like $res->content, qr{\Q<pre>&lt;X&gt;aa'&amp;</pre>\E};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3, name => 'default README and LICENSE';

test {
  my $c = shift;
  server ({
    'README' => 1,
    'myREADME' => q{<p>aa'&},
    'LICENSE' => q{<X>aa'&},
    '.htaccess' => q{
      ReadmeName myREADME
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{\Q<pre>&lt;p&gt;aa'&amp;</pre>\E};
          like $res->content, qr{\Q<pre>&lt;X&gt;aa'&amp;</pre>\E};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3, name => 'default README and LICENSE';

test {
  my $c = shift;
  server ({
    'myREADME.ja.txt' => qq{<p>aa'&\xE4\xB8\x80\x00},
    'LICENSE.txt' => qq{<X>aa'&\xE4\xB8\x80\x00},
    '.htaccess' => q{
      ReadmeName myREADME
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<pre>&lt;p&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
          like $res->content, qr{<pre>&lt;X&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3, name => 'default README and LICENSE';

test {
  my $c = shift;
  server ({
    'myREADME.ja.html' => qq{<p>aa'&\xE4\xB8\x80\x00},
    'LICENSE.html' => qq{<X>aa'&\xE4\xB8\x80\x00},
    '.htaccess' => q{
      ReadmeName myREADME
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<p>aa'&\xE4\xB8\x80\x00};
          unlike $res->content, qr{<X>aa'&\xE4\xB8\x80\x00};
          unlike $res->content, qr{<pre>&lt;X&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4, name => 'README html';

test {
  my $c = shift;
  server ({
    'myREADME.ja.txt' => qq{<p>aa'&\xE4\xB8\x80\x00},
    'LICENSE.txt' => qq{<X>aa'&\xE4\xB8\x80\x00},
    '.htaccess' => q{
      AddDefaultCharset ISO-2022-JP
      ReadmeName myREADME
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<pre>&lt;p&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
          like $res->content, qr{<pre>&lt;X&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3, name => 'default README and LICENSE - AddDefaultCharset ignored';

test {
  my $c = shift;
  server ({
    'myREADME.ja.html' => qq{<p>aa'&\xE4\xB8\x80\x00},
    'LICENSE.html' => qq{<X>aa'&\xE4\xB8\x80\x00},
    '.htaccess' => q{
      ReadmeName myREADME
      AddDefaultCharset EUC-JP
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<p>aa'&\xE4\xB8\x80\x00};
          unlike $res->content, qr{<X>aa'&\xE4\xB8\x80\x00};
          unlike $res->content, qr{<pre>&lt;X&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 4, name => 'README html - AddDefaultCharset ignored';

test {
  my $c = shift;
  server ({
    'myREADME.ja.txt' => qq{<p>aa'&\x88\xEA\x00},
    'LICENSE.txt' => qq{<X>aa'&\x88\xEA\x00},
    '.htaccess' => q{
      IndexOptions +charset=shift_jis
      ReadmeName myREADME
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<pre>&lt;p&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
          unlike $res->content, qr{<pre>&lt;X&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 3, name => 'default README and LICENSE - IndexOptions charset';

test {
  my $c = shift;
  server ({
    'myREADME.ja.html' => qq{<p>aa'&\x88\xEA\x00},
    'LICENSE.html' => qq{<X>aa'&\x88\xEA\x00},
    '.htaccess' => q{
      ReadmeName myREADME
      IndexOptions +charset=shift_JIS
    },
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</>],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          like $res->content, qr{<p>aa'&\xE4\xB8\x80\x00};
          unlike $res->content, qr{<X>aa'&\xEF\xBF\xBD\x80\x00};
          unlike $res->content, qr{<X>aa'&\xE4\xB8\x80\x00};
          unlike $res->content, qr{<pre>&lt;X&gt;aa'&amp;\xE4\xB8\x80\x00</pre>};
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 5, name => 'README html - IndexOptions charset';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
