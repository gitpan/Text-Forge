package Text::Forge::ModPerl;

use strict;
use vars qw/ $VERSION /;
use Carp;
use Apache::Constants qw/ :common REDIRECT /;
use Apache::ModuleConfig ();
use base qw/ Text::Forge DynaLoader /;

BEGIN {
  # OPT_EXECCGI(); # preload according to Apache::PerlRun
  $VERSION = '2.03';
  Text::Forge::ModPerl->bootstrap( $VERSION ); # XXX check where this should go
  __PACKAGE__->mk_accessors(qw/ status request /);
}

sub DIR_CREATE {
  my $class = shift;
 
  bless my $cfg = {}, $class;
  $cfg->{ForgeINC} = [];
  $cfg->{ForgeCache} = 1;
  return $cfg;
}

sub ForgeINC ($$@) {
  my($cfg, $parms, $arg) = @_;

  push @{ $cfg->{ForgeINC} }, $arg;
}

sub ForgeCache ($$$) {
  my($cfg, $parms, $arg) = @_;

  $cfg->{ForgeCache} = $arg;
}

sub send_header {
  my $self = shift;

  return if $self->{header_sent}++;
  $self->{request}->send_http_header;
}

sub handler ($$) {
  my($class, $r) = @_ > 1 ? @_ : (__PACKAGE__, shift());

  my $filename = $r->filename;
  *0 = \$filename;

  $r->finfo; # Cached stat() structure
  return NOT_FOUND unless -r _ and -s _;
  return DECLINED if -d _;

  # Support Apache::Filter
  if (lc($r->dir_config('Filter')) eq 'on') {
    $r = $r->filter_register;
  }

  $r->content_type('text/html; charset=ISO-8859-1');

  my $forge = $class->new;
  $forge->{request} = $r;
  $forge->{status} = OK;

  my $cfg = Apache::ModuleConfig->get($r);
  eval {
    local @Text::Forge::FINC = @{ $cfg->{ForgeINC} || [] };
    local $Text::Forge::CACHE = $cfg->{ForgeCache};
    $forge->send($filename);
  };
 
  if ($@) {
    $r->log_error(__PACKAGE__ . ": $@");
    return SERVER_ERROR;
  }

  return $forge->status;
}

sub redirect {
  my $self = shift;
  my($url, $status) = @_;

  my $r = $self->{request};
  $r->content_type('text/html');
  $r->header_out(Location => $url);
  $self->{header_sent} = 1; # Apache handles headers if status not OK
  $self->{status} = $status || REDIRECT;
}

1;
