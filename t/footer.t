use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  server ({
    '1.html' => q{ggg</BODY></html>},
    '2.html' => q{ggg</HTMl >},
    '3.html' => q{ggg},
    '4.txt' => q{ggg</body>},
    '5/index.html' => q{A</body>B},
  })->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</1.html>, q{ggg</BODY></html>}],
      [q</2.html>, q{ggg</HTMl >}],
      [q</3.html>, q{ggg}],
      [q</4.txt>, q{ggg</body>}],
      [q</LIST>, qr{</html>}],
      [q</5/>, q{A</body>B}],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          if (ref $x->[1]) {
            like $res->content, $x->[1];
          } else {
            is $res->content, $x->[1];
          }
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 6, name => 'no footer';

test {
  my $c = shift;
  server ({
    '1.html' => q{ggg</BODY></html>},
    '2.html' => q{ggg</HTMl >},
    '3.html' => q{ggg},
    '4.txt' => q{ggg</body>},
    '5/index.html' => q{A</html>B},
  }, html_footer => 'A<b&')->then (sub {
    my $server = $_[0];
    my $p = Promise->resolve;
    for my $x (
      [q</1.html>, q{gggA<b&</BODY></html>}],
      [q</2.html>, q{gggA<b&</HTMl >}],
      [q</3.html>, q{gggA<b&}],
      [q</4.txt>, q{ggg</body>}],
      [q</LIST>, qr{A<b&</html>$}],
      [q</5/>, q{AA<b&</html>B}],
    ) {
      $p = $p->then (sub {
        return GET ($server, $x->[0]);
      })->then (sub {
        my $res = $_[0];
        test {
          is $res->code, 200;
          if (ref $x->[1]) {
            like $res->content, $x->[1];
          } else {
            is $res->content, $x->[1];
          }
        } $c, name => $x->[0];
      });
    }
    return $p->then (sub {
      return $server->stop;
    })->then (sub { done $c; undef $c });
  });
} n => 2 * 6, name => 'with footer';

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
