package Text::Forge::ModPerl;

use ExtUtils::MakeMaker;
use Apache::ExtUtils qw( command_table );
use Apache::src ();

my @directives = (
  {
    name         => 'ForgeINC',
    errmsg       => 'search paths for forge parts',
    args_how     => 'ITERATE',
    req_override => 'OR_ALL',
  },

  {
    name         => 'ForgeCache',
    errmsg       => 'On or Off',
    args_how     => 'FLAG',
    req_override => 'OR_ALL',
  },
);
 
command_table(\@directives);

WriteMakefile(
    'NAME'	=> 'Text::Forge::ModPerl',
    'VERSION_FROM' => 'ModPerl.pm', # finds $VERSION
    'INC'          => Apache::src->new->inc,  
);

__END__
