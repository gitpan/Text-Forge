package Text::Forge::MemCache;

# XXX Debuging code is haphazard 

# Setting these values in a BEGIN block doesn't work.  The BEGIN
# block is called twice, wiping out any preloaded templates in 
# the parent process.
unless (defined $Max_Templates) {
  # Public globals
  $Max_Templates = 0;
  $Min_Templates = 0;
  $Debug         = 0;

  # Private globals
  $Template_Count = 0;
  $Total_Fetches  = 0;
  $Total_Hits     = 0;
  %Cache          = ();    
}

use strict;
use vars qw( 
             $Max_Templates $Min_Templates $Debug $Template_Count %Cache 
             $Total_Fetches $Total_Hits
           );
use Carp;

sub _debug {
  my $self = shift;

  print STDERR "CACHE [$Min_Templates/$Template_Count/$Max_Templates]: ", 
               join(' ', @_), "\n"; 
}          

sub _evict {
  my $self = shift;

  my @paths = sort { $Cache{ $b }->{age} <=> $Cache{ $a }->{age} } keys %Cache;

  if ($Debug) {
    foreach(@paths) {
      printf STDERR "%50s %d\n", $_, $Cache{$_}->{age};
    }
  }
  
  while($Template_Count > $Min_Templates) {
    last unless @paths;
    delete $Cache{ shift @paths };
    $Template_Count--;
  }
}

sub fetch {
  my $self = shift;
  my $path = shift;

  $path or croak 'no path supplied';

  if ($Debug) {
    $self->_debug( $Cache{ $path } ? "cache hit $path" : "cache miss $path" );
  }

  $Total_Fetches++;
  return undef unless exists $Cache{ $path };
  $Total_Hits++;
  
  if ($Max_Templates) {
    foreach(keys %Cache) { $Cache{ $_ }->{age}++ } 
    $Cache{ $path }->{age} = 0;
  }

  $Cache{ $path }->{sub};
}

sub store { 
  my $self = shift;
  my($path, $sub) = @_;

  $path or croak 'no path supplied';

  if ($Max_Templates) {
    foreach(keys %Cache) { $Cache{ $_ }->{age}++ }
    $self->_evict if $Template_Count > $Max_Templates;
  }

  $self->_debug("storing $path") if $Debug;

  $Template_Count++ unless exists $Cache{ $path };
  $Cache{ $path }->{sub}   = $sub;
  $Cache{ $path }->{age}   = 0;
}

sub delete {
  my $self = shift;
  my $path = shift;

  $path or croak 'no path supplied';   

  return unless exists $Cache{ $path };

  delete $Cache{ $path };
  --$Template_Count;
}

sub delete_all {
  my $self = shift;

  $Template_Count = 0;
  $Total_Fetches  = 0;
  $Total_Hits     = 0;
  %Cache          = ();       
}

sub max_templates { (@_ > 1 ? $Max_Templates = $_[1] : $Max_Templates) }
sub min_templates { (@_ > 1 ? $Min_Templates = $_[1] : $Min_Templates) }

sub is_cached { exists $Cache{ $_[1] } }  

# Apache::Status plugin

sub modperl_status {
  my($r, $q) = @_;

  my $lru  = ($Max_Templates ? 'Enabled' : 'Disabled');
  my $sort = ($ENV{PATH_INFO} =~ /age/ ? 'age' : 'path');

  my $perf = sprintf '%.2f', ($Total_Hits * 100 / ($Total_Fetches || 1));

  my @s = (<<EOF
<P><B>Configuration</B><P>

<TABLE BORDER=0>
<TR>
  <TD>Max Templates</TD><TD><B>$Max_Templates</B></TD>
  <TD>&nbsp;&nbsp;&nbsp;</TD>
  <TD>Debug</TD><TD><B>$Debug</B></TD>
</TR>
<TR>
  <TD>Min Templates</TD><TD><B>$Min_Templates</B></TD>
  <TD>&nbsp;&nbsp;&nbsp;</TD>
  <TD>LRU Replacement</TD><TD><B>$lru</B></TD>
</TR>
</TABLE>

<P><B>Cached Templates (hit rate $perf%)</B><P>

<TABLE BORDER=0>
<TR><TD><B><A HREF="$ENV{SCRIPT_NAME}/path/?$ENV{QUERY_STRING}">Path</A></B></TD><TD><B><A HREF="$ENV{SCRIPT_NAME}/age/?$ENV{QUERY_STRING}">Age</A></B></TD></TR>
EOF
  );
 
  my @keys = sort {
               (
                 $sort eq 'age' ? $Cache{ $a }->{age} <=> $Cache{ $b }->{age} 
                                : $a cmp $b
               )
             } keys %Cache;
 
  foreach my $path (@keys) {
    push @s, "<TR><TD>$path</TD>",
             "<TD ALIGN=RIGHT>$Cache{ $path }->{age}</TD></TR>";
  } 

  push @s, <<EOF;
</TABLE>
EOF

  return \@s;
}

eval {
  if (Apache->module('Apache::Status')) {
    Apache::Status->menu_item(
      'forge-memcache' => 'Text::Forge::MemCache',
      \&modperl_status
    );
  }
};

1;

__END__

=head1 NAME 

Text::Forge::MemCache - Memory Cache for Text::Forge Templates

=head1 SYNOPSIS

 use Text::Forge;
 my $forge = new Text::Forge;
 $forge->cache_module('Text::Forge::MemCache');

=head1 DESCRIPTION

The Text::Forge::MemCache class allows templates to be cached in
memory for faster execution.  Running previously cached templates 
requires no disk access, and completely by-passes the parsing and 
compilation phases.  This is the default cache module for
Text::Forge and its subclasses.

The class implements a Least Recently Used (LRU) replacement algorithm 
to limit memory consumption.  The two package globals, $Max_Templates
and $Min_Templates control the upper and lower boundaries.  If the
number of cached templates exceeds $Max_Templates, then templates
are evicted from the cache on an LRU basis until no more than
$Min_Templates remain.  

Setting $Max_Templates to zero disables the replacement algorithm 
altogether; templates are always cached and are never evicted.  
This is the default value, since the replacement algorithm is
somewhat expensive.

If $Max_Templates is set to a positive value, $Min_Templates should
be set appropriately.  Setting $Min_Templates to zero causes the
entire cache to be flushed once $Max_Templates has been exceeded, and
is not recommended.

Note that evicting cached templates will not release the memory back 
to the kernel (i.e. the process size will not decrease).  
Instead, the memory will be released to the perl interpreter, making
it available for other purposes within your application.

Under mod_perl, this module adds an entry for Apache::Status, which
allows you to view the state of the cache.  All cached templates
are displayed, along with their relative ages in the replacement
algorithm.  If the replacement algorithm has been disabled, all of
the ages will remain fixed at zero.  You must load the Apache::Status
module prior to Text::Forge::MemCache in order to have the status
entry appear.

=head1 AUTHOR

Copyright 1998-1999, Maurice Aubrey E<lt>maurice@hevanet.comE<gt>.
All rights reserved.
 
This module is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

Text::Forge::NoCache, Text::Forge, Apache::Status

=cut
