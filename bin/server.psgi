# -*- perl -*-
use strict;
use warnings;
use Path::Tiny;
use Furuike::Web;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

my $docroot = $ENV{FURUIKE_DOCUMENT_ROOT}
    // die "|FURUIKE_DOCUMENT_ROOT| is not specified";

return Furuike::Web->psgi_app (path ($docroot));

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
