use strict;
use Getopt::Long qw( GetOptions );
use Test::More qw( no_plan );

sub save_output($$) {
  my($file, $doc) = @_;

  my $path = "templates/$file-$Text::Forge::VERSION.out";
  ! -e $path or die "refusing to write '$path': file already exists";
  open my $fh, '>', $path or die "unable to write '$path': $!";
  print $fh $doc;
  close $fh or die "error closing '$path': $!";  
}

sub matches_file($$) {
  my($file, $doc) = @_;
 
  open my $fh, '<', $file or die "unable to read '$file': $!";
  my $fdoc = do { local $/; <$fh> };
  is($doc, $fdoc, "cmp $file");
}

if (-d 't') {
  chdir 't' or die "unable to chdir 't': $!";
}
unshift(@INC, "../blib/lib", "../blib/arch");

use_ok('Text::Forge');
like($Text::Forge::VERSION, qr/\d+(\.\d+)+/, 'version');

my %opt;
GetOptions(\%opt, 'save');

my $forge = Text::Forge->new;
ok($forge, 'constructor');

unshift @Text::Forge::FINC, 'templates';

my $doc = $forge->trap_send('forge');
matches_file('templates/forge.out', $doc);
save_output('forge', $doc) if $opt{save};

# We had a line numbering problem when a newline was used as the code operator.
# The newline was being consumed and threw the numbers off by one.
my $template = <<EOF;
<%

  thisisasyntaxerror; # on line three hopefully! %>
EOF
eval { $doc = $forge->trap_send(\$template) };
like($@, qr/\s+at\s+SCALAR.*?\s+line\s+3\./, 'line count with newline');
