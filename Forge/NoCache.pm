package Text::Forge::NoCache;

use strict;

sub fetch      { undef }
sub store      { undef }
sub delete     { undef }
sub delete_all { undef }
sub is_cached  { undef }

1;

__END__

=head1 NAME 

Text::Forge::NoCache - Cache Stub for Text::Forge 

=head1 SYNOPSIS

 use Text::Forge;
 my $forge = new Text::Forge;
 $forge->cache_module('Text::Forge::NoCache');

=head1 DESCRIPTION

This module is just a stub that implements the Text::Forge
caching interface but does not actually perform any caching.

This is useful when working under persistent environments
like mod_perl and you want your changes to take effect
immediately.

=head1 AUTHOR

Copyright 1998-1999, Maurice Aubrey E<lt>maurice@hevanet.comE<gt>.
All rights reserved.
 
This module is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

Text::Forge::MemCache, Text::Forge

=cut
