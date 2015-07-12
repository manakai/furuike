use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

for my $path (
  q</notfoind>,
  q</not/found>,
  #q<//hoge>,
  q</!-$>,
  q</%%>,
  q</ho//>,
  q</foo.txt>,
  q</foo.html>,
  q</favicon.ico>,
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

run_tests;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
