package Text::Forge::ModPerl;

our $MP = $ENV{USE_MOD_PERL};

if ($ENV{USE_MOD_PERL} == 1) {
  require Apache;
} elsif ($ENV{USE_MOD_PERL} == 2) {
  require Apache2;
} else {
  unless (eval { require Apache } || eval { require Apache2 }) {
    warn "mod_perl not found; ", __PACKAGE__, " will not be installed.\n";
    require ExtUtils::MakeMaker;
    ExtUtils::MakeMaker::WriteEmptyMakefile(NAME => __PACKAGE__);
    return;
  }
}

# check whether we loaded mod_perl 1.x or 2.x
require mod_perl;
$MP = $mod_perl::VERSION >= 1.99 ? 2 : 1;

if ($MP == 2) {
  warn "Configuring for mod_perl 2.x\n";
  require ModPerl::MM;

  # mod_perl 2.x doesn't need XS for custom directives so we tell
  # WriteMakefile to ignore them.
  ModPerl::MM::WriteMakefile(NAME => __PACKAGE__, XS => {}, C => []);
} else { # mod_perl 1.x
  warn "Configuring for mod_perl 1.x\n";
  require ExtUtils::MakeMaker;
  require Apache::ExtUtils;
  require Apache::src;

  # If you modify these directives, make sure you
  # change @APACHE_MODULE_COMMANDS in ModPerl.pm too
  my @directives = (
    {
      name         => 'ForgeINC',
      errmsg       => 'template search path',
      args_how     => 'ITERATE',
      req_override => 'OR_ALL',
    },
  
    {
      name         => 'ForgeCache',
      errmsg       => 'on or off',
      args_how     => 'FLAG',
      req_override => 'OR_ALL',
    },
  );
 
  Apache::ExtUtils::command_table(\@directives);

  ExtUtils::MakeMaker::WriteMakefile(
    NAME => __PACKAGE__,
    VERSION_FROM => 'ModPerl.pm',
    INC  => Apache::src->new->inc,  
  );
}

__END__
