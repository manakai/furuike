package Tests;
use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->parent->child ('t_deps/modules/*/lib');
use Test::More;
use Test::X1;
use File::Temp;
use AnyEvent;
use Promise;
use Promised::File;
use Promised::Plackup;
use Web::UserAgent::Functions qw(http_get);

our @EXPORT;
push @EXPORT, grep { not /^\$/ } @Test::More::EXPORT;
push @EXPORT, @Test::X1::EXPORT;

sub import ($;@) {
  my $from_class = shift;
  my ($to_class, $file, $line) = caller;
  no strict 'refs';
  for (@_ ? @_ : @{$from_class . '::EXPORT'}) {
    my $code = $from_class->can ($_)
        or die qq{"$_" is not exported by the $from_class module at $file line $line};
    *{$to_class . '::' . $_} = $code;
  }
} # import

my $root_path = path (__FILE__)->parent->parent->parent->absolute;

push @EXPORT, qw(server);
sub server (;$%) {
  my $files = shift || {};
  my %args = @_;
  my $server = Promised::Plackup->new;
  $server->{_temp} = my $temp = File::Temp->newdir;
  $server->envs->{FURUIKE_DOCUMENT_ROOT} = $temp;
  $server->plackup ($root_path->child ('plackup'));
  $server->set_option ('--host' => '127.0.0.1');
  $server->set_option ('--app' => $root_path->child ('bin/server.psgi'));
  $server->set_option ('--server' => 'Twiggy');
  my $p = Promise->resolve;
  for my $name (keys %$files) {
    my $path = path ("$temp/$name");
    $p = $p->then (sub {
      my $f = Promised::File->new_from_path ($path->parent);
      return $f->mkpath;
    })->then (sub {
      my $f = Promised::File->new_from_path ("$temp/$name");
      if (ref $files->{$name} eq 'SCALAR') {
        my $cmd = Promised::Command->new (['ln', '-s', ${$files->{$name}}, path ($name)->basename]);
        $cmd->wd (path ("$temp/$name")->parent);
        return $cmd->run->then (sub { return $cmd->wait })->then (sub {
          die $_[0] unless $_[0]->exit_code == 0;
        });
      } elsif (ref $files->{$name} eq 'HASH' and
               $files->{$name}->{unreadable}) {
        return ($files->{$name}->{directory} ? $f->mkpath : $f->write_byte_string (''))->then (sub {
          my $cmd = Promised::Command->new (['chmod', 'ugo-r', "$temp/$name"]);
          return $cmd->run->then (sub { return $cmd->wait })->then (sub {
            die $_[0] unless $_[0]->exit_code == 0;
          });
        });
      } elsif (ref $files->{$name} eq 'HASH' and
               $files->{$name}->{directory}) {
        return $f->mkpath;
      } else {
        return $f->write_byte_string ($files->{$name});
      }
    });
  }
  return $server->start->then (sub {
    return $p->then (sub { return $server });
  });
} # server

push @EXPORT, qw(GET);
sub GET ($$;%) {
  my ($server, $path, %args) = @_;
  my $host = $server->get_host;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    my $headers = {%{$args{header_fields} or {}}};
    $headers->{'Accept-Language'} = $args{langs} if defined $args{langs};
    http_get
        url => qq<http://$host$path>,
        basic_auth => $args{basic_auth},
        header_fields => $headers,
        params => $args{params},
        timeout => 30,
        anyevent => 1,
        max_redirect => 0,
        cb => sub {
          $ok->($_[1]);
        };
  });
} # GET

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
