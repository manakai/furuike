# -*- perl -*-
use strict;
use warnings;
use Furuike::Web;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

return Furuike::Web->psgi_app;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
