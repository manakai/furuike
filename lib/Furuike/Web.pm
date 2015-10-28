package Furuike::Web;
use strict;
use warnings;
use Web::DomainName::Punycode;
use Wanage::HTTP;
use Wanage::URL;
use Encode;
use AnyEvent::IO;
use Promise;
use Promised::File;
use Furuike::HTAccessParser;

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

my $MIMETypeMapping = {
  'application/x-javascript' => 'text/javascript',
  'application/x-ms-jscript' => 'text/javascript',
  'application/x-perl' => 'text/perl',
  'text/pod' => 'text/perl',
};

my $MIMETypeToPriority = {};
{
  my $i = 1;
  $MIMETypeToPriority->{$_} = $i++ for reverse qw(
    text/html text/plain
    image/png image/jpeg image/vnd.microsoft.icon image/gif
    application/pdf
  );
}

my $MIMETypeToNoSniff = {};
$MIMETypeToNoSniff->{$_} = 1 for qw(
  text/plain text/html application/octet-stream
);

my $CharsetTypeByMIMEType = {
  'text/html' => 'default',
  'text/plain' => 'default',
  'text/css' => 'default',
  'text/javascript' => 'default',
  'text/xml' => 'default',
  'text/x-component' => 'default',
  'text/perl' => 'default',
  'application/xml' => 'default',
  'application/xml-dtd' => 'default',
  'text/xml-external-parsed-entity' => 'default',
  'application/xml-external-parsed-entity' => 'default',
  'text/x-h2h' => 'default',
  'text/cache-manifest' => 'utf-8',
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

sub new_config () {
  return {
    default_charset => 'utf-8',
    ext_to_mime_type => {%$ExtToMIMEType},
    ext_to_charset => {%$ExtToCharset},
    ext_to_encoding => {%$ExtToEncoding},
    directory_index => ['index'],
    header_name => 'HEADER',
    readme_name => 'README',
    license_name => 'LICENSE',
    virtual => {is_directory => 1, children => {}},
  };
} # new_config

sub file_name_to_metadata ($$) {
  my $config = $_[0];

  # {base_name}.{lang}.{type}.{charset}.{encoding}

  my $file = {file_name => $_[1], suffixes => []};

  my @suffix = split /\./, $_[1], -1;
  $file->{base_name} = shift @suffix;

  if (@suffix and my $type = $config->{ext_to_encoding}->{$suffix[-1]}) {
    unshift @{$file->{suffixes}}, $suffix[-1];
    $file->{encoding} = $type;
    pop @suffix;
  }

  if (@suffix and my $type = $config->{ext_to_charset}->{$suffix[-1]}) {
    $file->{charset} = $type;
    unless ($config->{ext_to_mime_type}->{$suffix[-1]}) {
      unshift @{$file->{suffixes}}, $suffix[-1];
      pop @suffix;
    }
  }

  if (@suffix and my $type = $config->{ext_to_mime_type}->{$suffix[-1]}) {
    unshift @{$file->{suffixes}}, $suffix[-1];
    $file->{type} = $type;
    pop @suffix;
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

  if (not defined $file->{type}) {
    if ($file->{base_name} eq $config->{readme_name} or
        $file->{base_name} eq $config->{license_name} or
        $file->{base_name} eq $config->{header_name}) {
      $file->{type} = 'text/plain';
    }
  }

  return $file;
} # file_name_to_metadata

sub conneg ($$$$$$) {
  my ($http, $config, $names, $dir_path, $specified_names, $filter) = @_;
  return undef unless @$specified_names;
  my $bns = {};
  {
    my $i = 1;
    for (reverse @$specified_names) {
      $bns->{$_} = $i++;
    }
  }
  my $bn_pattern = join '|', map { quotemeta $_ } @$specified_names;
  my $files = [grep &$filter, map {
    if (/\A($bn_pattern)\./) {
      my $bn = $1;
      my $meta = file_name_to_metadata $config, $_;
      $meta->{name_priority} = $bns->{$1};
      if (length $_ <= length join '.', $bn, @{$meta->{suffixes}}) {
        ($meta);
      } else {
        ();
      }
    } else {
      ();
    }
  } @$names];

  my $lang_to_priority = {};
  {
    my $i = 1;
    for (reverse @{$http->accept_langs}) {
      $lang_to_priority->{$_} = $i++;
    }
  }
  for (@$files) {
    $_->{type_priority} = $MIMETypeToPriority->{$_->{type} // ''} || 0;
    $_->{lang_priority} = $lang_to_priority->{lc ($_->{lang} // '')} || 0;
    $_->{charset_priority} = ($_->{charset} // '') eq 'utf-8' ? 1 : 0;
  }
  $files = [sort {
    $b->{name_priority} <=> $a->{name_priority} ||
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
    return $_[0]; # or undef
  }, sub {
    undef $select_file;
    die $_[0];
  });
} # conneg

sub send_file ($$$$$$) {
  my ($http, $config, $path, $file, $meta, $status) = @_;
  # XXX if large file
  return $file->stat->then (sub {
    my $mtime = $_[0]->[9];
    return $file->read_byte_string->then (sub {
      $http->set_status ($status);
      $http->set_response_last_modified ($mtime);
      my $type = $meta->{type};
      if (defined $type) {
        my $charset = $meta->{charset};
        if (not defined $charset) {
          my $charset_type = $CharsetTypeByMIMEType->{$type} // '';
          if ($charset_type eq 'default') {
            if ($meta->{base_name} eq $config->{readme_name} or
                $meta->{base_name} eq $config->{header_name}) {
              $charset = $config->{index_options}->{charset};
            }
            $charset //= $config->{default_charset};
          } elsif ($charset_type eq 'utf-8') {
            $charset = 'utf-8';
          } elsif ($type =~ m{\+xml\z}) {
            if ($meta->{base_name} eq $config->{readme_name} or
                $meta->{base_name} eq $config->{header_name}) {
              $charset = $config->{index_options}->{charset};
            }
            $charset //= $config->{default_charset};
          } elsif ($type =~ m{\+json\z}) {
            $charset = 'utf-8';
          }
        }
        if (defined $charset) {
          $http->set_response_header ('Content-Type' => "$type; charset=$charset");
        } else {
          $http->set_response_header ('Content-Type' => $type);
        }
        if ($MIMETypeToNoSniff->{$type}) {
          $http->set_response_header ('X-Content-Type-Options' => 'nosniff');
        }
      }
      if (defined $meta->{lang}) {
        $http->set_response_header ('Content-Language' => $meta->{lang});
        $http->set_response_header ('Vary' => 'Accept-Language');
      }
      $http->set_response_header ('Content-Encoding' => $meta->{encoding})
          if defined $meta->{encoding};

      HEADER: for (@{$config->{headers} or []}) {
        if (defined $_->[2]) {
          CHK: {
            for (@{$_->[2]}) {
              if ($_->[0] eq '=') {
                last CHK if $meta->{file_name} eq $_->[1];
              } elsif ($_->[0] eq '^') {
                last CHK if $meta->{file_name} =~ /^\Q$_->[1]\E/;
              } elsif ($_->[0] eq '*') {
                last CHK if $meta->{file_name} =~ /\Q$_->[1]\E/;
              }
            }
            next HEADER;
          }
          $http->add_response_header ($_->[0], $_->[1]);
        } else {
          $http->add_response_header ($_->[0], $_->[1]);
        }
      }

      if (defined $type and $type eq 'text/html' and
          defined $config->{html_footer_ref}) {
        my $x = $_[0];
        $x =~ s{(?=</[Bb][Oo][Dd][Yy])}{${$config->{html_footer_ref}}} or
        $x =~ s{(?=</[Hh][Tt][Mm][Ll])}{${$config->{html_footer_ref}}} or
        ($x .= ${$config->{html_footer_ref}});
        $http->send_response_body_as_ref (\$x);
      } else {
        $http->send_response_body_as_ref (\($_[0]));
      }
      $http->close_response_body;
      access_log $http, $status, 'File', $path;
    });
  });
} # send_file

sub send_directory ($$$$$) {
  my ($http, $config, $path_segments, $dir_path, $file) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    aio_readdir $dir_path, sub {
      my ($names) = @_ or return $ng->($!);
      return $ok->($names);
    };
  })->then (sub {
    my $names = $_[0];
    my $has_readme;
    my $has_header;
    my $has_license;
    my @image_file;
    my @other_file;
    my $t = '';
    return $file->stat->then (sub {
      my $mtime = $_[0]->[9];
      $http->set_status (200);
      $http->set_response_last_modified ($mtime);
      $http->set_response_header ('Content-Type' => 'text/html; charset=utf-8');
      $http->set_response_header ('X-Content-Type-Options' => 'nosniff');

      for (@{$config->{headers} or []}) {
        $http->add_response_header ($_->[0], $_->[1]) unless defined $_->[2];
      }

      my $dir_name = $dir_path->basename;
      $t .= q{<!DOCTYPE HTML>};
      $t .= sprintf q{<link rel=stylesheet href="%s">},
          htescape $config->{index_style_sheet}
          if defined $config->{index_style_sheet};
      $t .= sprintf q{
        <title>%s</title>
      },
          htescape (join '/', @$path_segments);

      for (sort { $a cmp $b } grep { /\A$Segment\z/o } @$names) {
        $has_readme = 1 if $config->{readme_name} eq $_;
        $has_header = 1 if $config->{header_name} eq $_;
        $has_license = 1 if $config->{license_name} eq $_;
        my $parsed = file_name_to_metadata $config, $_;
        my @t = ('<li>');
        my $name = $parsed->{base_name};
        my $is_image = defined $parsed->{type} && $parsed->{type} =~ /^image/;
        if ($is_image) {
          push @t, sprintf q{<a href="%s"><img src="%s" alt></a> },
              htescape $parsed->{file_name},
              htescape $parsed->{file_name};
        }
        push @t, q{<span class=name>};
        push @t, sprintf q{<a href="%s">%s</a>},
            htescape $name, htescape $name;
        for (@{$parsed->{suffixes}}) {
          $name .= '.' . $_;
          push @t, sprintf q{.<a href="%s">%s</a>},
              htescape $name, htescape $_;
        }
        push @t, q{</span>};
        my $desc = $config->{index_descs}->{$parsed->{file_name}} //
                   $config->{index_descs}->{$parsed->{base_name}};
        if (defined $desc) {
          push @t, sprintf q{ <span class=desc>%s</span>},
              htescape $desc;
        }
        if ($is_image) {
          push @image_file, join '', @t;
        } else {
          push @other_file, join '', @t;
        }
      } # $names

      if ($has_header) {
        my $f = Promised::File->new_from_path ($dir_path->child ($config->{header_name}));
        return $f->lstat->then (sub {
          if (-f $_[0] and not -l $_[0]) {
            return [$dir_path, $f, {type => 'text/html'}];
          }
          return undef;
        });
      }
      return conneg $http, $config, $names, $dir_path, [$config->{header_name}], sub {
        return 0 unless defined $_->{type};
        return 0 unless $_->{type} eq 'text/html';
        return 0 if defined $_->{encoding};
        return 1;
      };
    })->then (sub {
      return 0 unless defined $_[0];
      my ($path, $f, $meta) = @{$_[0]};
      my $charset = $meta->{charset} // $config->{index_options}->{charset} // 'utf-8';
      if ($charset eq 'utf-8') {
        if ($meta->{type} eq 'text/html') {
          return $f->read_char_string->then (sub {
            $http->send_response_body_as_text ($_[0]);
          })->then (sub { return 1 });
        }
      } else {
        ## Note that $charset must be a valid encoding label
        # XXX Use Web::Encoding
        if ($meta->{type} eq 'text/html') {
          return $f->read_byte_string->then (sub {
            $http->send_response_body_as_text (decode $charset, $_[0]);
          })->then (sub { return 1 });
        }
      }
    })->then (sub {
      unless ($_[1]) {
        my $x = '';
        my $n = @$path_segments - 3;
        $t .= sprintf q{<h1><a href=/ rel=top><code>%s</code></a>%s</h1>},
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
            } @$path_segments);
      }

      if (@image_file) {
        $t .= sprintf q{<section id=images><h1>Images</h1><ul>%s</ul></section>},
            join '', @image_file;
      }
      if (@other_file) {
        $t .= sprintf q{<section id=files><h1>Files</h1><ul>%s</ul></section>},
            join '', @other_file;
      }

      $http->send_response_body_as_text ($t);

      if ($has_readme) {
        my $f = Promised::File->new_from_path ($dir_path->child ($config->{readme_name}));
        return $f->lstat->then (sub {
          if (-f $_[0] and not -l $_[0]) {
            return [$dir_path, $f, {type => 'text/plain'}];
          }
          return undef;
        });
      }
      return conneg $http, $config, $names, $dir_path, [$config->{readme_name}], sub {
        return 0 unless defined $_->{type};
        return 0 unless $_->{type} eq 'text/html' or
                        $_->{type} eq 'text/plain';
        return 0 if defined $_->{encoding};
        return 1;
      };
    })->then (sub {
      return unless defined $_[0];
      my ($path, $f, $meta) = @{$_[0]};
      my $charset = $meta->{charset} // $config->{index_options}->{charset} // 'utf-8';
      if ($charset eq 'utf-8') {
        if ($meta->{type} eq 'text/html') {
          return $f->read_char_string->then (sub {
            $http->send_response_body_as_text ($_[0]);
          });
        } elsif ($meta->{type} eq 'text/plain') {
          return $f->read_char_string->then (sub {
            $http->send_response_body_as_text
                (sprintf '<pre>%s</pre>', htescape $_[0]);
          });
        }
      } else {
        ## Note that $charset must be a valid encoding label
        # XXX Use Web::Encoding
        if ($meta->{type} eq 'text/html') {
          return $f->read_byte_string->then (sub {
            $http->send_response_body_as_text (decode $charset, $_[0]);
          });
        } elsif ($meta->{type} eq 'text/plain') {
          return $f->read_byte_string->then (sub {
            $http->send_response_body_as_text
                (sprintf '<pre>%s</pre>', htescape decode $charset, $_[0]);
          });
        }
      }
    })->then (sub {
      if ($has_license) {
        my $f = Promised::File->new_from_path ($dir_path->child ($config->{license_name}));
        return $f->lstat->then (sub {
          if (-f $_[0] and not -l $_[0]) {
            return [$dir_path, $f, {type => 'text/plain'}];
          }
          return undef;
        });
      }
      return conneg $http, $config, $names, $dir_path, [$config->{license_name}], sub {
        return 0 unless defined $_->{type};
        return 0 unless $_->{type} eq 'text/plain';
        return 0 if defined $_->{encoding};
        return 1;
      };
    })->then (sub {
      return unless defined $_[0];
      my ($path, $f, $meta) = @{$_[0]};
      return $f->read_char_string->then (sub {
        $http->send_response_body_as_text
            (sprintf '<section id=LICENSE><h1 lang=en><a href=LICENSE rel=license>License</a></h1><pre>%s</pre></section>', htescape $_[0]);
      });
    })->then (sub {
      if (defined $config->{html_footer_ref}) {
        $http->send_response_body_as_ref ($config->{html_footer_ref});
      }
      $http->send_response_body_as_ref (\'</html>');
      $http->close_response_body;
      access_log $http, 200, 'Directory', $dir_path;
    });
  });
} # send_directory

sub error ($$$$$$) {
  my ($http, $config, $docroot, $status, $reason, $path) = @_;
  if (defined (my $doc = $config->{error_document}->{$status})) {
    ## Note that symlink check is not performed for ErrorDocument
    my $dir_path = $docroot->child (@$doc[0..($#$doc-1)]);
    my $error_config = new_config;
    return check_htaccess ($docroot, $error_config)->then (sub {
      return Promised::File->new_from_path ($dir_path)->is_directory;
    })->then (sub {
      if ($_[0]) {
        return Promise->new (sub {
          my ($ok, $ng) = @_;
          aio_readdir $dir_path, sub {
            my ($names) = @_ or return $ng->($!);
            return $ok->($names);
          };
        });
      } else {
        return [];
      }
    })->then (sub {
      for (@{$_[0]}) {
        if ($_ eq $doc->[-1]) {
          my $f = Promised::File->new_from_path ($dir_path->child ($doc->[-1]));
          return $f->is_file->then (sub { # no symlink check
            if ($_[0]) {
              return [$dir_path,
                      $f,
                      file_name_to_metadata $error_config, $doc->[-1]];
            }
            return undef;
          });
        }
      }
      return conneg $http, $error_config, $_[0], $dir_path, [$doc->[-1]], sub {
        return 0 unless defined $_->{type};
        return 0 unless $_->{type} eq 'text/html' or
                        $_->{type} eq 'text/plain';
        return 0 if defined $_->{encoding};
        return 1;
      };
    })->then (sub {
      if (defined $_[0]) {
        return send_file $http, $error_config, $_[0]->[0], $_[0]->[1], $_[0]->[2], $status;
      } else {
        $http->set_status ($status);
        $http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
        $http->send_response_body_as_ref (\"$status $reason");
        $http->close_response_body;
        access_log $http, $status, $reason, $path;
      }
    });
  } else {
    $http->set_status ($status);
    $http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
    $http->send_response_body_as_ref (\"$status $reason");
    $http->close_response_body;
    access_log $http, $status, $reason, $path;
  }
} # error

sub redirect ($$$$) {
  my ($http, $status, $url, $reason) = @_;
  $http->set_status ($status);
  $http->set_response_header ('Location' => $url);
  $http->set_response_header ('Content-Type' => 'text/html; charset=utf-8');
  $http->send_response_body_as_ref (\sprintf q{<!DOCTYPE html><title>Redirect</title><a href="%s">Next</a>}, htescape $url);
  $http->close_response_body;
  access_log $http, $status, $reason;
} # redirect

sub check_htaccess ($$) {
  my $config = $_[1];
  my $htaccess_path = $_[0]->child ('.htaccess');
  my $f = Promised::File->new_from_path ($htaccess_path);
  return $f->is_file->then (sub {
    if ($_[0]) {
      return $f->read_char_string->then (sub {
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
        for my $directive (@$data) {
          if ($directive->{name} eq 'AddType') {
            my $type = $directive->{type};
            $type =~ tr/A-Z/a-z/; ## ASCII case-insensitive.
            $type = $MIMETypeMapping->{$type} // $type;
            $config->{ext_to_mime_type}->{$_} = $type for @{$directive->{exts}};
          } elsif ($directive->{name} eq 'AddCharset') {
            my $type = $directive->{type};
            $type =~ tr/A-Z/a-z/; ## ASCII case-insensitive.
            $config->{ext_to_charset}->{$_} = $type for @{$directive->{exts}};
          } elsif ($directive->{name} eq 'AddEncoding') {
            my $type = $directive->{type};
            $type =~ tr/A-Z/a-z/; ## ASCII case-insensitive.
            $config->{ext_to_encoding}->{$_} = $type for @{$directive->{exts}};
          } elsif ($directive->{name} eq 'AddLanguage') {
            my $type = $directive->{type};
            $type =~ tr/A-Z/a-z/; ## ASCII case-insensitive.
            if ($type =~ /\A[a-z][a-z](?:-[a-z][a-z]|)\z/) {
              for (@{$directive->{exts}}) {
                warn "Bad directive - AddLanguage $type $_"
                    unless $type eq lc $_ and /^[a-z][a-z]/;
              }
            } else {
              warn "Bad directive - AddLanguage $type";
            }
          } elsif ($directive->{name} eq 'AddDefaultCharset') {
            my $type = $directive->{value};
            $type =~ tr/A-Z/a-z/; ## ASCII case-insensitive.
            die "Bad directive - AddDefaultCharset $type"
                unless $type =~ /\A[a-z0-9_.+:-]+\z/;
            $config->{default_charset} = $type;
          } elsif ($directive->{name} eq 'Header') {
            push @{$config->{headers} ||= []},
                [$directive->{header_name}, $directive->{header_value},
                 $directive->{files}];
          } elsif ($directive->{name} eq 'Options') {
            my $type = $directive->{option_name};
            die "Bad Options - $type" unless {
              MultiViews => 1,
              ExecCGI => 1,
              Indexes => 1,
            }->{$type};
            if ($directive->{'+'}) {
              $config->{options}->{$type} = $directive->{option_value} // '';
            } elsif ($directive->{'-'}) {
              die "Bad directive - Options -$directive->{option_name}=$directive->{option_value}"
                  if defined $directive->{option_value};
              delete $config->{options}->{$type};
            } else {
              $config->{options} = {};
              $config->{options}->{$type} = $directive->{option_value} // '';
            }
          } elsif ($directive->{name} eq 'IndexOptions') {
            my $type = $directive->{option_name};
            die "Bad IndexOptions - $type" unless {
              NameWidth => 1,
              DescriptionWidth => 1,
              TrackModified => 1,
              HTMLTable => 1,
              IconsAreLinks => 1,
              charset => 1,
              FancyIndexing => 1,
            }->{$type};
            $directive->{option_value} =~ tr/A-Z/a-z/
                if $type eq 'charset' and defined $directive->{option_value};
            if ($directive->{'+'}) {
              $config->{index_options}->{$type} = $directive->{option_value} // '';
            } elsif ($directive->{'-'}) {
              die "Bad directive - IndexOptions -$directive->{option_name}=$directive->{option_value}"
                  if defined $directive->{option_value};
              delete $config->{index_options}->{$type};
            } else {
              $config->{index_options} = {};
              $config->{index_options}->{$type} = $directive->{option_value} // '';
            }
          } elsif ($directive->{name} eq 'DirectoryIndex') {
            for (@{$directive->{values}}) {
              die "Bad directive - DirectoryIndex $_" unless /\A$Segment\z/o;
            }
            $config->{directory_index} = $directive->{values};
          } elsif ($directive->{name} eq 'IndexStyleSheet') {
            $config->{index_style_sheet} = $directive->{url};
          } elsif ($directive->{name} eq 'AddDescription') {
            $config->{index_descs}->{$directive->{file_name}} = $directive->{value};
          } elsif ($directive->{name} eq 'ReadmeName') {
            die "Bad directive - ReadmeName $directive->{value}"
                unless $directive->{value} =~ /\A$Segment\z/o;
            $config->{readme_name} = $directive->{value};
          } elsif ($directive->{name} eq 'HeaderName') {
            die "Bad directive - ReadmeName $directive->{value}"
                unless $directive->{value} =~ /\A$Segment\z/o;
            $config->{header_name} = $directive->{value};
          } elsif ($directive->{name} eq 'ErrorDocument') {
            if ($directive->{path} =~ m{\A(?:/$Segment)+\z}o) {
              $config->{error_document}->{$directive->{status}}
                  = [grep { length } split m{/}, $directive->{path}];
            } else {
              die "Bad path $directive->{path}";
            }
          } elsif ($directive->{name} eq 'Redirect') {
            my @from = split m{/}, $directive->{from}, -1;
            shift @from;
            my $from_last = pop @from;
            my $current = $config->{virtual};
            for (@from) {
              $current->{children}->{$_} ||= {};
              $current = $current->{children}->{$_};
              $current->{is_directory} = 1;
            }
            unless ($from_last eq '' and $directive->{all_descendants}) {
              $current->{children}->{$from_last} ||= {};
              $current = $current->{children}->{$from_last};
            }
            if (defined $directive->{to}) {
              my $to = $directive->{to};
              for (keys %{$config->{redirect_top} or {}}) {
                $to =~ s{^\Q$_\E}{/} and last;
              }
              $current->{location} = $to;
            }
            $current->{status} = $directive->{status};
            $current->{all} = $directive->{all_descendants}
                if $directive->{all_descendants};
            $current->{rule} = $directive->{rule} // '';
          } elsif ($directive->{name} eq 'FuruikeRedirectTop') {
            $config->{redirect_top}->{$directive->{url}} = 1; 
         } elsif ($directive->{name} eq 'IndexIgnore' or
                   $directive->{name} eq 'AddIcon' or
                   $directive->{name} eq 'RemoveHandler') {
            # ignored
          } elsif ($directive->{name} eq 'AddHandler') {
            if ($directive->{type} eq 'cgi-script') {
              # ignored
            } else {
              die "Unknown handler |$directive->{type}|";
            }
          } else {
            die "Unknown directive |$directive->{name}|";
          }
        }
      });
    }
  });
} # check_htaccess

sub psgi_app ($$$) {
  my ($class, $docroot, $footerref) = @_;
  return sub {
    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    return $http->send_response (onready => sub {

      my $p = $docroot;
      my $f;

      my $config = new_config;
      my $current_virtual = $config->{virtual};
      $config->{html_footer_ref} = $footerref;

      my $path = $http->url->{path};
      if ($path =~ s{,([^/,]*)\z}{}) {
        my $comma = percent_decode_c $1;
        if ($comma eq 'imglist' or $comma eq 'imglist-detail') {
          return redirect $http, 301, 'LIST', 'Directory';
        }
        return error $http, $config, $docroot,
            404, 'Comma tool not found', undef;
      }

      my @p = my @path = map { percent_decode_c $_ } split m{/}, $path, -1;
      shift @path if @path > 1;

      my $add_path; $add_path = sub {
        my $segment = $_[0];
        if (not @path and $segment eq '') { # last segment (directory)
          $current_virtual = $current_virtual->{children}->{$segment};
          if (defined $current_virtual->{status}) {
            if (defined $current_virtual->{location}) {
              return redirect $http, $current_virtual->{status}, $current_virtual->{location}, 'Redirect';
            } else {
              return error $http, $config, $docroot,
                  $current_virtual->{status}, 'Error', undef;
            }
          } elsif (not defined $p) {
            return error $http, $config, $docroot,
                404, 'Directory not found', undef;
          }

          $f ||= Promised::File->new_from_path ($p);
          return $f->lstat->then (sub {
            if (not -l $_[0] and -d $_[0]) {
              return Promise->new (sub {
                my ($ok, $ng) = @_;
                aio_readdir $p, sub {
                  my ($names) = @_ or return $ng->($!);
                  return $ok->($names);
                };
              })->then (sub {
                return conneg $http, $config, $_[0], $p, $config->{directory_index}, sub { 1 };
              })->then (sub {
                if (defined $_[0]) {
                  return send_file $http, $config, $_[0]->[0], $_[0]->[1], $_[0]->[2], 200;
                } else {
                  return send_directory $http, $config, \@p, $p, $f;
                }
              });
            } else {
              return error $http, $config, $docroot,
                  404, 'Directory not found', $p;
            }
          }, sub {
            return error $http, $config, $docroot,
                404, 'Directory not found', $p;
          });
        } elsif (@path and $segment =~ /\A$Segment\z/o) { # non-last segment
          $current_virtual = $current_virtual->{children}->{$segment} ||= {};
          if ($current_virtual->{all}) {
            if (defined $current_virtual->{location}) {
              my $url = $current_virtual->{location};
              if ($current_virtual->{rule} eq 'sw2005') {
                $url .= join '%2F%2F', map { percent_encode_c $_ } @path;
              } elsif ($current_virtual->{rule} eq 'plusslash') {
                my @p = split m{/}, $http->original_url->{path}, -1;
                shift @p;
                @p = splice @p, -@path;
                $url .= join '/', map {
                  my $x = $_;
                  $x =~ s{\+}{%2F}g;
                  $x;
                } @p;
              } elsif (not $current_virtual->{all} eq 'ignore') {
                $url .= join '/', map { percent_encode_c $_ } @path;
              }
              return redirect $http, $current_virtual->{status},
                  $url, 'Redirect';
            } else {
              return error $http, $config, $docroot,
                  $current_virtual->{status}, 'Error', undef;
            }
          } elsif (not $current_virtual->{is_directory}) {
            if (defined $current_virtual->{status} and
                not defined $current_virtual->{location}) {
              return error $http, $config, $docroot,
                  $current_virtual->{status}, 'Error', undef;
            } elsif (not defined $p) {
              return error $http, $config, $docroot,
                  404, 'Directory not found', undef;
            }
          } elsif (not defined $p) {
            return $add_path->(shift @path);
          }

          $p = $p->child ($segment);
          $f = Promised::File->new_from_path ($p);
          return $f->lstat->catch (sub { return undef })->then (sub {
            my $stat = $_[0];
            if (defined $stat and -l $stat) {
              if ($current_virtual->{is_directory}) {
                undef $p;
                undef $f;
                return $add_path->(shift @path);
              } else {
                return error $http, $config, $docroot,
                    404, 'Bad path', $p;
              }
            } elsif (defined $stat and -d $stat) {
              return check_htaccess ($p, $config)->then (sub {
                return $add_path->(shift @path);
              });
            } elsif ($current_virtual->{is_directory}) {
              undef $p;
              undef $f;
              return $add_path->(shift @path);
            } else {
              return error $http, $config, $docroot,
                  404, 'Directory not found', $p;
            }
          });
        } elsif (not @path and $segment =~ /\A$Segment\z/o) { # last segment
          if ($segment eq 'LIST') {
            if (defined $p) {
              $f ||= Promised::File->new_from_path ($p);
              return $f->lstat->then (sub {
                if (not -l $_[0] and -d $_[0]) {
                  return Promise->new (sub {
                    my ($ok, $ng) = @_;
                    aio_readdir $p, sub {
                      my ($names) = @_ or return $ng->($!);
                      return $ok->($names);
                    };
                  })->then (sub {
                    return send_directory $http, $config, \@p, $p, $f;
                  });
                } else {
                  return error $http, $config, $docroot,
                      404, 'Directory not found', $p;
                }
              }, sub {
                return error $http, $config, $docroot,
                    404, 'Directory not found', $p;
              });
            }
          }

          $current_virtual = $current_virtual->{children}->{$segment};
          if (defined $current_virtual->{status}) {
            if (defined $current_virtual->{location}) {
              my $url = $current_virtual->{location};
              if ($current_virtual->{rule} eq 'mypage' or
                  $current_virtual->{rule} eq 'mypagepuny') {
                # ...?mypage={mypage}&_charset_={charset}
                my $query = $http->url->{query} // '';
                $query = '_charset_=euc-jp&mypage=' . $query unless $query =~ /=/;
                my $q = {map { percent_decode_b $_ } map { split /=/, $_, 2 } split /[;&]/, $query};
                my $charset = $q->{_charset_} // 'euc-jp';
                $charset = 'utf-8' unless $charset eq 'euc-jp';
                my $page = decode $charset, $q->{mypage} // '';
                if ($current_virtual->{rule} eq 'mypagepuny') {
                  $page =~ s{//+}{/}g;
                  my $x = (percent_encode_c encode_punycode ($page));
                  $x =~ s/%20/_/g;
                  $url .= $x;
                } else {
                  $url .= percent_encode_c $page;
                }
              }
              return redirect $http, $current_virtual->{status}, $url, 'Redirect';
            } else {
              return error $http, $config, $docroot,
                  $current_virtual->{status}, 'Error', undef;
            }
          } elsif ($current_virtual->{is_directory} and not defined $p) {
            return redirect $http, 301, (percent_encode_c $segment) . '/', 'Directory';
          } elsif (not defined $p) {
            return error $http, $config, $docroot,
                404, 'File not found', undef;
          }

          $p = $p->child ($segment);
          $f = Promised::File->new_from_path ($p);
          return $f->lstat->catch (sub { return undef })->then (sub {
            my $stat = $_[0];
            if (defined $stat and -l $stat) {
              if ($current_virtual->{is_directory}) {
                return redirect $http, 301, (percent_encode_c $segment) . '/', 'Directory';
              } else {
                return error $http, $config, $docroot,
                    404, 'Bad path', $p;
              }
            } else {
              if (defined $stat and -f $stat) {
                return send_file $http, $config, $p, $f, (file_name_to_metadata $config, $p->basename), 200;
              } elsif ($current_virtual->{is_directory} or
                       defined $stat and -d $stat) {
                return redirect $http, 301, (percent_encode_c $segment) . '/', 'Directory';
              } else {
                my $parent_path = $p->parent;
                return Promise->new (sub {
                  my ($ok, $ng) = @_;
                  aio_readdir $parent_path, sub {
                    my ($names) = @_ or return $ng->($!);
                    return $ok->($names);
                  };
                })->then (sub {
                  return conneg ($http, $config, $_[0], $parent_path, [$segment], sub { 1 });
                })->then (sub {
                  if (defined $_[0]) {
                    return send_file $http, $config, $_[0]->[0], $_[0]->[1], $_[0]->[2], 200;
                  } else {
                    return error $http, $config, $docroot,
                        404, 'File not found', $p;
                  }
                });
              }
            }
          });
        } else {
          return error $http, $config, $docroot,
              404, 'Bad path', $p;
        }
      }; # $add_path

      return Promise->resolve->then (sub {
        return check_htaccess $p, $config;
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
