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
  $self->{data} = {};
  my $onerror = $self->onerror;
  $s =~ s/\x0D\x0A/\x0A/g;
  $s =~ s/\x0D/\x0A/g;
  my $in_mod;
  for (split /\x0A/, $s) {
    if (/^\s*#/) {
      #
    } elsif ($in_mod and m{^\s*</IfModule>\s*$}) {
      $in_mod = 0;
    } elsif ($in_mod) {
      #
    } elsif (/^\s*([A-Za-z0-9]+)\s+(.+)$/) {
      my $name = $1;
      my $args = $2;
      my $parser = $DirectiveParsers->{$name};
      if ($parser) {
        $parser->($self, $name, $args);
      } else {
        $onerror->(level => 'm', type => 'htaccess:unknown directive', value => $name);
      }
    } elsif (m{^\s*<IfModule\s+([^<>]+)>\s*$}) {
      $onerror->(level => 'w', type => 'htaccess:IfModule', value => $1);
      $in_mod = 1;
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
    push @{$self->{data}->{$name} ||= []}, {value => $1};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:value:syntax error', value => $args);
  }
}; # AddDefaultCharset

$DirectiveParsers->{IndexStyleSheet} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*"([^"]*)"\s*$}) {
    push @{$self->{data}->{$name} ||= []}, {url => $1};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:url:syntax error', value => $args);
  }
}; # IndexStyleSheet

$DirectiveParsers->{IndexIgnore} =
$DirectiveParsers->{DirectoryIndex} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*\S+(?:\s+\S+)*\s*$}) {
    push @{$self->{data}->{$name} ||= []}, {values => [grep { length } split /\s+/, $args]};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:values:syntax error', value => $args);
  }
}; # DirectoryIndex

$DirectiveParsers->{AddType} =
$DirectiveParsers->{AddEncoding} =
$DirectiveParsers->{AddLanguage} =
$DirectiveParsers->{AddHandler} =
$DirectiveParsers->{AddCharset} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*([A-Za-z0-9_.,+:/-]+)\s+(\S+(?:\s+\S+)*)\s*$}) {
    my $type = $1;
    my $exts = [grep { length } map { s/^\.//; $_ } split /\s+/, $2];
    push @{$self->{data}->{$name} ||= []}, {type => $type, exts => $exts};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:Add:syntax error', value => $args);
  }
}; # AddType

$DirectiveParsers->{ErrorDocument} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*([45][0-9][0-9])\s+(\S+)\s*$}) {
    push @{$self->{data}->{$name} ||= []}, {status => $1, path => $2};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:ErrorDocument:syntax error', value => $args);
  }
}; # ErrorDocument

$DirectiveParsers->{Redirect} = sub {
  my ($self, $name, $args) = @_;
  if ($args =~ m{^\s*(30[12378]|permanent|temp|seeother)\s+(/\S+)\s+(\S+)\s*$}) {
    push @{$self->{data}->{$name} ||= []}, {status => $1, from => $2, to => $3};
  } elsif ($args =~ m{^\s*([45][0-9][0-9]|gone)\s+(/\S+)\s*$}) {
    push @{$self->{data}->{$name} ||= []}, {status => $1, from => $2};
  } elsif ($args =~ m{^\s*(/\S+)\s+(\S+)\s*$}) {
    push @{$self->{data}->{$name} ||= []}, {status => 302, from => $1, to => $2};
  } else {
    $self->onerror->(level => 'm', type => 'htaccess:Redirect:syntax error', value => $args);
  }
  $self->{data}->{$name}->[-1]->{status} = {
    gone => 410,
    permanent => 301,
    temp => 302,
    seeother => 303,
  }->{$self->{data}->{$name}->[-1]->{status}} || $self->{data}->{$name}->[-1]->{status};
}; # Redirect

$DirectiveParsers->{Options} =
$DirectiveParsers->{IndexOptions} = sub {
  my ($self, $name, $args) = @_;
  for (grep { length } split /\s+/, $args) {
    my $v = {};
    $v->{$1} = 1 if s/^([+-])//;
    $v->{value} = $1 if s/=(.*)$//;
    return $self->onerror->(level => 'm', type => 'htaccess:IndexOptions:syntax error', value => $_)
        unless /\A[A-Za-z0-9]+\z/;
    $v->{name} = $_;
    push @{$self->{data}->{$name} ||= []}, $v;
  }
}; # IndexOptions

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
