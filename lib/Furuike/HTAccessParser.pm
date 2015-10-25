package Furuike::HTAccessParser;
use strict;
use warnings;

sub new ($) {
  return bless {}, $_[0];
} # new

sub onerror ($;$) {
  if (@_ > 1) {
    $_[0]->{onerror} = $_[1];
  }
  return $_[0]->{onerror} || sub { warn "@_" };
} # onerror

my $DirectiveParsers = {};

sub parse_char_string ($$) {
  my ($self, $s) = @_;
  $self->{data} = [];
  my $onerror = $self->onerror;
  $s =~ s/\x0D\x0A/\x0A/g;
  $s =~ s/\x0D/\x0A/g;
  my $in_mod;
  my $in_files;
  for (split /\x0A/, $s) {
    if (/^\s*#/) {
      #
    } elsif (defined $in_mod and m{^\s*</IfModule>\s*$}) {
      $in_mod = undef;
    } elsif (defined $in_mod and $in_mod eq 'Ignore') {
      #
    } elsif (defined $in_files and m{^\s*</Files>\s*$}) {
      $in_files = undef;
    } elsif (/^\s*([A-Za-z0-9]+)\s+(.+)$/) {
      my $name = $1;
      my $args = $2;
      my $parser = $DirectiveParsers->{$name};
      if ($parser and (not defined $in_files or $name eq 'Header')) {
        $parser->($self, $name, $args, $in_files);
      } else {
        $onerror->(level => 'm', type => 'htaccess:unknown directive', value => $name);
      }
    } elsif (m{^\s*<IfModule\s+([^<>]+)>\s*$}) {
      $in_mod = $1;
      if ($in_mod eq 'mod_headers.c' or $in_mod eq 'Furuike') {
        #
      } else {
        $onerror->(level => 'w', type => 'htaccess:IfModule', value => $in_mod);
        $in_mod = 'Ignore';
      }
    } elsif (defined $in_files) {
      $onerror->(level => 'm', type => 'htaccess:broken line', value => $_);
    } elsif (m{^\s*<Files\s+"([^"]+)">\s*$}) {
      $in_files = [['=', $1]];
    } elsif (m{^\s*<Files\s+([A-Za-z0-9_.-]+)>\s*$}) {
      $in_files = [['=', $1]];
    } elsif (m{^\s*<Files\s+~\s+"([A-Za-z0-9_.-]+(?:\|[A-Za-z0-9_.-]+)*)">\s*$}) {
      $in_files = [map { ['*', $_] } split /\|/, $1];
    } elsif (m{^\s*<Files\s+~\s+"\^\(([A-Za-z0-9_.-]+)\|([A-Za-z0-9_.-]+)\)">\s*$}) {
      $in_files = [['^', $1], ['^', $2]];
    } elsif (/\S/) {
      $onerror->(level => 'm', type => 'htaccess:broken line', value => $_);
    }
  }
  return delete $self->{data};
} # parse_char_string

$DirectiveParsers->{HeaderName} =
$DirectiveParsers->{ReadmeName} =
$DirectiveParsers->{AddDefaultCharset} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*(\S+)\s*$}) {
    push @{$self->{data}}, {name => $name, value => $1};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:value:syntax error', value => $args);
  }
}; # AddDefaultCharset

$DirectiveParsers->{IndexStyleSheet} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*"([^"]*)"\s*$}) {
    push @{$self->{data}}, {name => $name, url => $1};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:url:syntax error', value => $args);
  }
}; # IndexStyleSheet

$DirectiveParsers->{IndexIgnore} =
$DirectiveParsers->{RemoveHandler} =
$DirectiveParsers->{DirectoryIndex} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*\S+(?:\s+\S+)*\s*$}) {
    push @{$self->{data}}, {name => $name, values => [grep { length } split /\s+/, $args]};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:values:syntax error', value => $args);
  }
}; # DirectoryIndex

$DirectiveParsers->{AddType} =
$DirectiveParsers->{AddEncoding} =
$DirectiveParsers->{AddLanguage} =
$DirectiveParsers->{AddHandler} =
$DirectiveParsers->{AddCharset} = sub {
  my ($self, $name, $args, $in_files) = @_;
  if ($args =~ m{^\s*([A-Za-z0-9_.,+:/-]+)\s+(\S+(?:\s+\S+)*)\s*$}) {
    my $type = $1;
    my $exts = [grep { length } map { s/^\.//; $_ } split /\s+/, $2];
    push @{$self->{data}}, {name => $name, type => $type, exts => $exts,
                            files => $in_files};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:Add:syntax error', value => $args);
  }
}; # AddType

$DirectiveParsers->{ErrorDocument} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*([45][0-9][0-9])\s+(\S+)\s*$}) {
    push @{$self->{data}}, {name => $name, status => $1, path => $2};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:ErrorDocument:syntax error', value => $args);
  }
}; # ErrorDocument

$DirectiveParsers->{Redirect} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*(30[12378]|permanent|temp|seeother)\s+(/\S+)\s+(\S+)\s*$}) {
    push @{$self->{data}}, {name => $name, status => $1, from => $2, to => $3};
  } elsif ($args =~ m{^\s*([45][0-9][0-9]|gone)\s+(/\S+)\s*$}) {
    push @{$self->{data}}, {name => $name, status => $1, from => $2};
  } elsif ($args =~ m{^\s*(/\S+)\s+(\S+)\s*$}) {
    push @{$self->{data}}, {name => $name, status => 302, from => $1, to => $2};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:Redirect:syntax error', value => $args);
  }
  $self->{data}->[-1]->{all_descendants} = 1
      if $self->{data}->[-1]->{from} =~ m{/$};
  $self->{data}->[-1]->{status} = {
    gone => 410,
    permanent => 301,
    temp => 302,
    seeother => 303,
  }->{$self->{data}->[-1]->{status}} || $self->{data}->[-1]->{status};
}; # Redirect

$DirectiveParsers->{RedirectMatch} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*(30[12378]|permanent|temp|seeother)\s+(/[A-Za-z0-9_/-]+)/\.\*\s+(\S+)\s*$}) {
    push @{$self->{data}}, {name => 'Redirect', status => $1, from => $2, to => $3, all_descendants => 1};
  } elsif ($args =~ m{^\s*(30[12378]|permanent|temp|seeother)\s+(/[A-Za-z0-9_/-]+)\$\s+(\S+)\s*$}) {
    push @{$self->{data}}, {name => 'Redirect', status => $1, from => $2, to => $3};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:RedirectMatch:syntax error', value => $args);
  }
  $self->{data}->[-1]->{status} = {
    gone => 410,
    permanent => 301,
    temp => 302,
    seeother => 303,
  }->{$self->{data}->[-1]->{status}} || $self->{data}->[-1]->{status};
}; # RedirectMatch

$DirectiveParsers->{Options} =
$DirectiveParsers->{IndexOptions} = sub {
  my ($self, $name, $args) = @_;
  for (grep { length } split /\s+/, $args) {
    my $v = {};
    $v->{$1} = 1 if s/^([+-])//;
    $v->{option_value} = $1 if s/=(.*)$//;
    return $self->onerror->(level => 'm', type => 'htaccess:options:syntax error', value => $_)
        unless /\A[A-Za-z0-9]+\z/;
    $v->{option_name} = $_;
    $v->{name} = $name;
    push @{$self->{data}}, $v;
  }
}; # IndexOptions

$DirectiveParsers->{Header} = sub {
  my ($self, $name, $args, $files) = @_;
  if ($args =~ m{^\s*add\s+([A-Za-z0-9-]+)\s+"((?:[\x20\x21\x23-\x5B\x5D-\x7E]|\\["\\])*)"\s*$}) {
    push @{$self->{data}}, {name => $name, header_name => $1, header_value => $2, files => $files};
    $self->{data}->[-1]->{header_value} =~ s/\\(["\\])/$1/ge;
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:Header:syntax error', value => $args);
  }
}; # Header

$DirectiveParsers->{FuruikeRedirectTop} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*(https?://[^/]+/)\s*$}) {
    push @{$self->{data}}, {name => $name, url => $1};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:FuruikeRedirectTop:syntax error', value => $args);
  }
}; # FuruikeRedirectTop

$DirectiveParsers->{AddDescription} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*"([^"]*)"\s+(\S+)\s*$}) {
    push @{$self->{data}}, {name => $name, file_name => $2, value => $1};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:AddDescription:syntax error', value => $args);
  }
}; # AddDescription

$DirectiveParsers->{AddIcon} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*\(([^(),\s]+),([^(),\s]+)\)\s+(\S+(?:\s+\S+)*)\s*$}) {
    my $data = {name => $name, alt => $1, url => $2};
    $data->{exts} = [grep { length } map { s/^\.//; $_ } split /\s+/, $3];
    push @{$self->{data}}, $data;
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:AddIcon:syntax error', value => $args);
  }
}; # AddIcon

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
