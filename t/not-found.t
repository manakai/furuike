use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

my $server = web_server;

for my $path (
  q</notfoind>,
  q</not/found>,
  q<//hoge>,
  q</!-$>,
  q</%%>,
  q</ho//>,
) {
  test {
    my $c = shift;
    my $host = $c->received_data->{host};
    GET ($c, $path)->then (sub {
      my $res = $_[0];
      test {
        is $res->code, 404;
        is $res->header ('Content-Type'), q{text/plain; charset=utf-8};
        is $res->content, q{404 Not Found};
      } $c;
      done $c;
      undef $c;
    });
  } wait => $server, n => 3, name => $path;
}

for my $path (
  q</ >,
  q</foo bar>,
) {
  test {
    my $c = shift;
    my $host = $c->received_data->{host};
    GET ($c, $path)->then (sub {
      my $res = $_[0];
      test {
        like $res->code, qr{^40[04]$};
      } $c;
      done $c;
      undef $c;
    });
  } wait => $server, n => 1, name => $path;
}

run_tests;
stop_servers;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
