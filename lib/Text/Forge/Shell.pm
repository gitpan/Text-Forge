package Text::Forge::Shell;

use strict;
use Getopt::Long qw/ GetOptions /;

sub run {
  my $cgi;
  GetOptions("cgi" => \$cgi);
  my $class = $cgi ? 'Text::Forge::CGI' : 'Text::Forge';

  eval "require $class" or die $@;

  push @ARGV, '-' unless @ARGV;
  foreach (@ARGV) {
    my $forge = $class->new;
    if ($_ eq '-') {
      my $doc = do { local $/; <STDIN> };
      $forge->send(\$doc);
    } else {
      $forge->send($_);
    }
  }

  exit 0;
}

1;
