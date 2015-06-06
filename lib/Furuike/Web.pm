package Furuike::Web;
use strict;
use warnings;
use Wanage::HTTP;

sub psgi_app ($) {
  my ($class) = @_;
  return sub {
    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    return $http->send_response (onready => sub {

      $http->set_status (404);
      $http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
      $http->send_response_body_as_ref (\"404 Not Found");
      $http->close_response_body;

    });
  };
} # psgi_app

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
