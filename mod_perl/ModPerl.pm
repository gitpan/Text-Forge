package Text::Forge::ModPerl;

# Based on Apache::Registry 2.01

$Debug = 0;

use strict;
use vars qw( $VERSION $Debug );
use Apache::Constants qw( :common &OPT_EXECCGI );
use Apache::ModuleConfig ();
use Text::Forge::CGI;

$VERSION = '0.05';

my $Is_Win32 = $^O eq 'MSWin32';

if ($ENV{MOD_PERL}) {
  no strict;
  @ISA = qw( DynaLoader );
  Text::Forge::ModPerl->bootstrap( $VERSION );
}

# SET DEFAULTS
sub DIR_CREATE {
  my $class = shift;

  bless my $cfg = {}, $class;
  $cfg->{'ForgeBuffer'}          = 0;
  $cfg->{'ForgeCacheModule'}     = 'Text::Forge::MemCache';
  $cfg->{'ForgeInitHandler'}     = undef;
  return $cfg;
}

sub ForgeTemplatePath ($$$) {
  my($cfg, $parms, $path) = @_;

  $cfg->{'ForgeTemplatePath'} = $path;
}

sub ForgeCacheModule ($$$) {
  my($cfg, $parms, $module) = @_;

  $cfg->{'ForgeCacheModule'} = $module;
}               

sub ForgeBuffer ($$$) {
  my($cfg, $parms, $flag) = @_;

  $cfg->{'ForgeBuffer'} = $flag;
}

sub ForgeInitHandler ($$$) {
  my($cfg, $params, $module) = @_;

  $cfg->{'ForgeInitHandler'} = $module;
}

sub debug {
  my $r   = shift;
  my $str = join '', @_;

  $r->log_error("[$$] Text::Forge::ModPerl $str");
}

sub handler {
  my($r, @args) = @_;

  my $filename = $r->filename;

  $r->finfo; # Cached stat() structure 
  return NOT_FOUND unless -r _ and -s _;
  return DECLINED if -d _;

  unless (-x _ or $Is_Win32) {
    $r->log_reason('file permissions deny server execution', $filename);
    return FORBIDDEN;
  }                           

  unless ($r->allow_options & OPT_EXECCGI) {
    $r->log_reason('options ExecCGI is off in this directory', $filename);
    return FORBIDDEN;
  }

  # debug($r, "running '$filename'") if $Debug;

  my $forge = new Text::Forge::CGI;

  if (my $cfg = Apache::ModuleConfig->get( $r )) {
    $forge->{template_path} = $cfg->{'ForgeTemplatePath'};
    $forge->{buffer}        = $cfg->{'ForgeBuffer'};
    $forge->{cache_module}  = $cfg->{'ForgeCacheModule'};
  
    if (my $handler = $cfg->{'ForgeInitHandler'}) {
      # debug($r, "running init handler '$handler'") if $Debug;
      no strict 'refs';
      (my $status, @args) = &{ $handler }($r, $forge, @args);  
      return $status unless $status == DECLINED;
    }
  }

  eval { $forge->send( $filename, @args ) };

  if ($@) {

    # XXX This needs work!
    # If CGI::Carp is loaded, let it handle the error.
    # Note the naseating hack to force CGI::Carp to handle it.
    # 
    # Warning: CGI::Carp is not logging the error if some content
    #          has already been sent to the client 
    #          (see line 346 of CGI::Carp). So we send the error ourselves.    
    if (exists $INC{'CGI/Carp.pm'}) {
      $r->log_error("Text::Forge::ModPerl: $@") if $r->bytes_sent;
      local *CGI::Carp::ineval = sub { 0 };
      die $@;
    }

    $r->log_error("Text::Forge::ModPerl: $@");
    return SERVER_ERROR;
  }

  OK;
}

1;
