package Text::Forge::ModPerl;

use ExtUtils::MakeMaker;

use Apache::ExtUtils ();
use Apache::src ();

my @apache_directives = 
  (
    { 
      name         => 'ForgeTemplatePath',
      errmsg       => 'a local path containing forge templates',
      args_how     => 'TAKE1',
      req_override => 'OR_ALL',
    },
    {
      name         => 'ForgeCacheModule',
      errmsg       => 'perl module which implements forge caching api',
      args_how     => 'TAKE1',
      req_override => 'OR_ALL',
    },
    {
      name         => 'ForgeBuffer',
      errmsg       => 'On or Off',
      args_how     => 'FLAG',
      req_override => 'OR_ALL',
    },
    {
      name         => 'ForgeInitHandler',
      errmsg       => 'perl module which implements initialization handler',
      args_how     => 'TAKE1',
      req_override => 'OR_ALL',
    },
  );

Apache::ExtUtils::command_table( \@apache_directives );

WriteMakefile(
    'NAME'	   => 'Text::Forge::ModPerl',
    'VERSION_FROM' => 'ModPerl.pm',
    'INC'          => Apache::src->new->inc,
);

__END__
