package Furuike::Web;
use strict;
use warnings;
use Wanage::HTTP;
use Wanage::URL;
use Promise;
use Promised::File;

sub access_log ($$$) {
  my ($http, $status, $type) = @_;
  print STDERR join "\t",
      'time:' . time,
      'client:' . $http->client_ip_addr->as_text,
      'method:' . $http->request_method,
      'url:' . $http->url->stringify,
      'status:' . $status,
      'response_type:' . $type;
  print STDERR "\n";
} # access_log

sub not_found ($$) {
  my ($http, $reason) = @_;
  $http->set_status (404);
  $http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
  $http->send_response_body_as_ref (\"404 $reason");
  $http->close_response_body;
  access_log $http, 404, $reason;
} # not_found

sub redirect ($$$) {
  my ($http, $status, $url) = @_;
  $http->set_status ($status);
  $http->set_response_header ('Location' => $url);
  $http->set_response_header ('Content-Type' => 'text/html; charset=utf-8');
  my $eurl = $url;
  $eurl =~ s/&/&amp;/g;
  $eurl =~ s/</&lt;/g;
  $eurl =~ s/>/&gt;/g;
  $eurl =~ s/"/&quot;/g;
  $http->send_response_body_as_ref (\sprintf q{<!DOCTYPE html><title>Redirect</title><a href="%s">Next</a>}, $eurl);
  $http->close_response_body;
  access_log $http, $status, 'Redirect';
} # redirect

sub send_file ($$) {
  my ($http, $file) = @_;
  # XXX if large file
  return $file->read_byte_string->then (sub {
    $http->set_status (200);
    #$http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
    $http->send_response_body_as_ref (\($_[0]));
    $http->close_response_body;
    access_log $http, 200, 'File';
  });
} # send_file

sub send_directory ($$) {
  my ($http, $directory) = @_;
  $http->set_status (200);
  #$http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
  $http->send_response_body_as_ref (\'Directory');
  $http->close_response_body;
  access_log $http, 200, 'Directory';
} # send_directory

sub psgi_app ($$) {
  my ($class, $docroot) = @_;
  return sub {
    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    return $http->send_response (onready => sub {

      my $path = $http->url->{path};
      my @path = map { percent_decode_c $_ } split m{/}, $path, -1;
      shift @path if @path > 1;

      my $p = $docroot;
      my $f;

      my $add_path; $add_path = sub {
        my $segment = $_[0];
        if ($segment eq '' and not @path) {
          $f ||= Promised::File->new_from_path ($p);
          return $f->is_directory->then (sub {
            if ($_[0]) {
              return send_directory $http, $f;
            } else {
              return not_found $http, 'Directory not found';
            }
          });
        } elsif ($segment =~ /\A[A-Za-z0-9_-][A-Za-z0-9_.-]*\z/) {
          $p = $p->child ($segment);
          $f = Promised::File->new_from_path ($p);
          return $f->is_symlink->then (sub {
            if ($_[0]) {
              return not_found $http, 'Bad path';
            } else {
              if (@path) { # non-last segment
                return $f->is_directory->then (sub {
                  if ($_[0]) {
                    return $add_path->(shift @path);
                  } else {
                    return not_found $http, 'Directory not found';
                  }
                });
              } else { # last segment
                return $f->is_file->then (sub {
                  if ($_[0]) {
                    return send_file $http, $f;
                  } else {
                    return $f->is_directory->then (sub {
                      if ($_[0]) {
                        return redirect $http, 301, (percent_encode_c $segment) . '/';
                      } else {
                        return not_found $http, 'File not found';
                      }
                    });
                  }
                });
              }
            }
          });
        } else {
          return not_found $http, 'Bad path';
        }
      }; # $add_path

      return Promise->resolve->then (sub {
        return $add_path->(shift @path);
      })->then (sub {
        undef $add_path;
      }, sub {
        undef $add_path;
        unless ($http->response_headers_sent) {
          $http->set_status (500, reason_phrase => 'Server error');
          $http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
          $http->send_response_body_as_ref (\'500 Server error');
          $http->close_response_body;
        }
        access_log $http, 500, 'Server error';
        warn $_[0];
      });
    });
  };
} # psgi_app

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
