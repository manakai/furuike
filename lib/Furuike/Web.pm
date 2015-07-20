package Furuike::Web;
use strict;
use warnings;
use Wanage::HTTP;
use Wanage::URL;
use AnyEvent::IO;
use Promise;
use Promised::File;

my $Segment = qr/~?[A-Za-z0-9_-][A-Za-z0-9_.-]*/;

sub htescape ($) {
  return $_[0] unless $_[0] =~ /[&<>"]/;
  my $e = $_[0];
  $e =~ s/&/&amp;/g;
  $e =~ s/</&lt;/g;
  $e =~ s/>/&gt;/g;
  $e =~ s/"/&quot;/g;
  return $e;
} # htescape

sub access_log ($$$;$) {
  my ($http, $status, $type, $path) = @_;
  print STDERR join "\t",
      'time:' . time,
      'client:' . $http->client_ip_addr->as_text,
      'method:' . $http->request_method,
      'url:' . $http->url->stringify,
      'status:' . $status,
      'response_type:' . $type,
      'response_file:' . ($path // '');
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
  $http->send_response_body_as_ref (\sprintf q{<!DOCTYPE html><title>Redirect</title><a href="%s">Next</a>}, htescape $url);
  $http->close_response_body;
  access_log $http, $status, 'Redirect';
} # redirect

my $ExtToMIMEType = {
  'html' => 'text/html',
  'txt' => 'text/plain',
  'css' => 'text/css',
  'js' => 'text/javascript',
  'json' => 'application/json',
  'png' => 'image/png',
  'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'ico' => 'image/vnd.microsoft.icon',
  'xml' => 'text/xml',
  'svg' => 'image/svg+xml',
  'xhtml' => 'application/xhtml+xml',
  'pdf' => 'application/pdf',
  'zip' => 'application/zip',
};

my $MIMETypeToPriority = {};
{
  my $i = 1;
  $MIMETypeToPriority->{$_} = $i++ for reverse qw(
    text/html text/plain
    image/png image/jpeg image/vnd.microsoft.icon image/gif
  );
}

my $CharsetTypeByMIMEType = {
  'text/html' => 'default',
  'text/plain' => 'default',
  'text/css' => 'default',
  'text/javascript' => 'default',
  'text/xml' => 'default',
  'application/xml' => 'default',
  'application/json' => 'utf-8',
};

my $ExtToCharset = {
  'u8' => 'utf-8',
  'sjis' => 'shift_jis',
  'euc' => 'euc-jp',
  'jis' => 'iso-2022-jp',
};

my $ExtToEncoding = {
  'gz' => 'gzip',
};

sub file_name_to_metadata ($) {
  # {base_name}.{lang}.{type}.{charset}.{encoding}

  my $file = {file_name => $_[0], suffixes => []};

  my @suffix = split /\./, $_[0], -1;
  $file->{base_name} = shift @suffix;

  if (@suffix and $ExtToEncoding->{$suffix[-1]}) {
    unshift @{$file->{suffixes}}, $suffix[-1];
    $file->{encoding} = $ExtToEncoding->{pop @suffix};
  }

  if (@suffix and $ExtToCharset->{$suffix[-1]}) {
    unshift @{$file->{suffixes}}, $suffix[-1];
    $file->{charset} = $ExtToCharset->{pop @suffix};
  }

  if (@suffix and $ExtToMIMEType->{$suffix[-1]}) {
    unshift @{$file->{suffixes}}, $suffix[-1];
    $file->{type} = $ExtToMIMEType->{pop @suffix};
  }

  if (defined $file->{charset}) {
    if (defined $file->{type}) {
      my $charset_type = $CharsetTypeByMIMEType->{$file->{type}};
      if (defined $charset_type and $charset_type eq 'default') {
        #
      } elsif ($file->{type} =~ m{\+xml\z}) {
        #
      } else {
        delete $file->{charset};
        delete $file->{type};
        $file->{base_name} = join '.', $file->{base_name}, @suffix, splice @{$file->{suffixes}}, 0, 2;
        return $file;
      }
    } else {
      delete $file->{charset};
      $file->{base_name} = join '.', $file->{base_name}, @suffix, shift @{$file->{suffixes}};
      return $file;
    }
  }

  if (@suffix and $suffix[-1] =~ /\A[a-z]{2}(?:-[A-Za-z]{2})?\z/) {
    unshift @{$file->{suffixes}}, $suffix[-1];
    $file->{lang} = pop @suffix;
    $file->{lang} =~ s/(-[A-Za-z]+)$/uc $1/e;
  }

  $file->{base_name} = join '.', $file->{base_name}, @suffix;
  return $file;
} # file_name_to_metadata

sub send_file ($$$$) {
  my ($http, $path, $file, $meta) = @_;
  # XXX if large file
  return $file->stat->then (sub {
    my $mtime = $_[0]->[9];
    return $file->read_byte_string->then (sub {
      $http->set_status (200);
      $http->set_response_last_modified ($mtime);
      my $type = $meta->{type};
      if (defined $type) {
        my $charset = $meta->{charset};
        if (not defined $charset) {
          my $charset_type = $CharsetTypeByMIMEType->{$type};
          if (defined $charset_type and $charset_type eq 'default') {
            $charset = 'utf-8';
          } elsif (defined $charset_type and $charset_type eq 'utf-8') {
            $charset = 'utf-8';
          } elsif ($charset_type =~ m{\+xml\z}) {
            $charset = 'utf-8';
          } elsif ($charset_type =~ m{\+json\z}) {
            $charset = 'utf-8';
          }
        }
        if (defined $charset) {
          $http->set_response_header ('Content-Type' => "$type; charset=$charset");
        } else {
          $http->set_response_header ('Content-Type' => $type);
        }
      }
      $http->set_response_header ('Content-Language' => $meta->{lang})
          if defined $meta->{lang};
      $http->set_response_header ('Content-Encoding' => $meta->{encoding})
          if defined $meta->{encoding};
      $http->send_response_body_as_ref (\($_[0]));
      $http->close_response_body;
      access_log $http, 200, 'File', $path;
    });
  });
} # send_file

sub send_directory ($$$$) {
  my ($http, $path_segments, $path, $file) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    aio_readdir $path, sub {
      my ($names) = @_ or return $ng->($!);
      return $ok->($names);
    };
  })->then (sub {
    my $names = $_[0];
    return $file->stat->then (sub {
      my $mtime = $_[0]->[9];
      $http->set_status (200);
      $http->set_response_last_modified ($mtime);
      $http->set_response_header ('Content-Type' => 'text/html; charset=utf-8');
      my $dir_name = $path->basename;
      my $x = '';
      my $n = @$path_segments - 3;
      my $t = sprintf q{
        <!DOCTYPE HTML><title>%s</title><h1><a href=/ rel=top><code>%s</code></a>%s</h1>
        <ul>
          %s
        </ul>
      },
          htescape (join '/', @$path_segments),
          htescape ($http->url->{host}.':'.$http->url->{port}),
          (join '/', map {
            $x .= percent_encode_c ($_) . '/';
            if (length $_) {
              sprintf q{<a href="%s" rel="%s"><code>%s</code></a>},
                  htescape $x,
                  (join ' ', ('up') x $n--) || 'self',
                  htescape $_;
            } else {
              '';
            }
          } @$path_segments),
          (join '', map {
            my $parsed = file_name_to_metadata $_;
            my @t = ('<li>');
            my $name = $parsed->{base_name};
            push @t, sprintf q{<a href="%s">%s</a>},
                htescape $name, htescape $name;
            for (@{$parsed->{suffixes}}) {
              $name .= '.' . $_;
              push @t, sprintf q{.<a href="%s">%s</a>},
                  htescape $name, htescape $_;
            }
            join '', @t;
          } sort { $a cmp $b } grep { /\A$Segment\z/o } @$names);
      $http->send_response_body_as_text ($t);
      $http->close_response_body;
      access_log $http, 200, 'Directory', $path;
    });
  });
} # send_directory

sub send_conneg ($$$) {
  my ($http, $p, $fallback) = @_;
  my $dir_path = $p->parent;
  my $base_name = $p->basename;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    aio_readdir $dir_path, sub {
      my ($names) = @_ or return $ng->($!);
      return $ok->($names);
    };
  })->then (sub {
    my $files = [map {
      if (/\A$base_name\./) {
        my $meta = file_name_to_metadata $_;
        if (length $_ <= length join '.', $base_name, @{$meta->{suffixes}}) {
          ($meta);
        } else {
          ();
        }
      } else {
        ();
      }
    } @{$_[0]}];

    my $i = 1;
    my $lang_to_priority = {};
    for (reverse @{$http->accept_langs}) {
      $lang_to_priority->{$_} = $i++;
    }
    for (@$files) {
      $_->{type_priority} = $MIMETypeToPriority->{$_->{type} // ''} || 0;
      $_->{lang_priority} = $lang_to_priority->{lc ($_->{lang} // '')} || 0;
      $_->{charset_priority} = ($_->{charset} // '') eq 'utf-8' ? 1 : 0;
    }
    $files = [sort {
      $b->{type_priority} <=> $a->{type_priority} ||
      $b->{lang_priority} <=> $a->{lang_priority} ||
      $b->{charset_priority} <=> $a->{charset_priority};
    } @$files];

    return undef unless @$files;

    my $select_file; $select_file = sub {
      my $file = shift @$files;
      return undef unless defined $file;
      my $path = $dir_path->child ($file->{file_name});
      my $f = Promised::File->new_from_path ($path);
      return $f->lstat->then (sub {
        if (not -l $_[0] and -f $_[0]) {
          return [$path, $f, $file];
        } else {
          return $select_file->();
        }
      }, sub {
        return $select_file->();
      });
    }; # $select_file

    return Promise->resolve ($select_file->())->then (sub {
      undef $select_file;
      return $_[0];
    }, sub {
      undef $select_file;
      die $_[0];
    });
  })->then (sub {
    return send_file $http, $_[0]->[0], $_[0]->[1], $_[0]->[2] if $_[0];
    return $fallback->();
  });
} # send_conneg

sub check_htaccess ($) {
  my $htaccess_path = $_[0]->child ('.htaccess');
  my $f = Promised::File->new_from_path ($htaccess_path);
  return $f->is_file->then (sub {
    if ($_[0]) {
      return $f->read_char_string->then (sub {
        use Furuike::HTAccessParser;
        my $parser = Furuike::HTAccessParser->new;
        my $has_fatal_error;
        $parser->onerror (sub {
          my %args = @_;
          if ($args{level} eq 'm') {
            $has_fatal_error = 1;
          }
          warn join ' ', %args;
        });
        my $data = $parser->parse_char_string ($_[0]);
        die "$htaccess_path is broken" if $has_fatal_error;
      });
    }
  });
} # check_htaccess

sub psgi_app ($$) {
  my ($class, $docroot) = @_;
  return sub {
    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    return $http->send_response (onready => sub {

      my $path = $http->url->{path};
      my @p = my @path = map { percent_decode_c $_ } split m{/}, $path, -1;
      shift @path if @path > 1;

      my $p = $docroot;
      my $f;

      my $add_path; $add_path = sub {
        my $segment = $_[0];
        if ($segment eq '' and not @path) { # last segment (directory)
          $f ||= Promised::File->new_from_path ($p);
          return $f->lstat->then (sub {
            if (not -l $_[0] and -d $_[0]) {
              return send_conneg $http, $p->child ('index'), sub {
                return send_directory $http, \@p, $p, $f;
              };
            } else {
              return not_found $http, 'Directory not found';
            }
          }, sub {
            return not_found $http, 'Directory not found';
          });
        } elsif ($segment =~ /\A$Segment\z/o) {
          $p = $p->child ($segment);
          $f = Promised::File->new_from_path ($p);
          return $f->lstat->catch (sub { return undef })->then (sub {
            my $stat = $_[0];
            if (defined $stat and -l $stat) {
              return not_found $http, 'Bad path';
            } elsif (@path) { # non-last segment
              if (defined $stat and -d $stat) {
                return check_htaccess ($p)->then (sub {
                  return $add_path->(shift @path);
                });
              } else {
                return not_found $http, 'Directory not found';
              }
            } else { # last segment
              if (defined $stat and -f $stat) {
                return send_file $http, $p, $f, file_name_to_metadata $p->basename;
              } elsif (defined $stat and -d $stat) {
                return redirect $http, 301, (percent_encode_c $segment) . '/';
              } else {
                return send_conneg $http, $p, sub {
                  return not_found $http, 'File not found';
                };
              }
            }
          });
        } else {
          return not_found $http, 'Bad path';
        }
      }; # $add_path

      return Promise->resolve->then (sub {
        return check_htaccess $p;
      })->then (sub {
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
