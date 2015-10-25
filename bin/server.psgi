# -*- perl -*-
use strict;
use warnings;
use Path::Tiny;
use Furuike::Web;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

my $docroot = $ENV{FURUIKE_DOCUMENT_ROOT}
    // die "|FURUIKE_DOCUMENT_ROOT| is not specified";

my $footer;
my $footer_file = $ENV{FURUIKE_HTML_FOOTER_FILE};
if (defined $footer_file) {
  $footer = path ($footer_file)->slurp;
}

return Furuike::Web->psgi_app (path ($docroot), defined $footer ? \$footer : undef);

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
