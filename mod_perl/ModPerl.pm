package Text::Forge::ModPerl;

our $VERSION = '2.04';

use constant MP2 => ($mod_perl::VERSION >= 1.99);

use strict;
use Carp;
use XSLoader ();

use base qw/ Text::Forge /;

XSLoader::load(__PACKAGE__, $VERSION) if $ENV{MOD_PERL};

BEGIN {
  my @const = qw/
    OK DECLINED FORBIDDEN SERVER_ERROR NOT_FOUND HTTP_MOVED_TEMPORARILY
    OR_ALL FLAG ITERATE
  /;
  if (MP2) {
    require APR::Table;
    require Apache::RequestRec;
    require Apache::RequestIO;
    require Apache::Module;
    require Apache::Log;
    require Apache::Const;
    Apache::Const->import(-compile => @const);
  
    # If you modify these directives, make sure you
    # change @directives in Makefile.PL too
    no strict 'subs';
    our @directives = (
      {
        name         => 'ForgeINC',
        errmsg       => 'Search paths for forge templates',
        args_how     => Apache::ITERATE,
        req_override => Apache::OR_ALL,
      },
    
      {
        name         => 'ForgeCache',
        errmsg       => 'On or Off',
        args_how     => Apache::FLAG,
        req_override => Apache::OR_ALL,
      },
    );
    Apache::Module::add(__PACKAGE__, \@directives);
  } else {
    require Apache::ModuleConfig;
    require Apache::Constants;
    # Create aliases to the new, mod_perl 2.x names
    no strict 'refs';
    foreach (@const) {
      *{"Apache::$_"} = \&{"Apache::Constants::$_"};
      *{__PACKAGE__ . "::$_"} = \&{"Apache::$_"};
    }
  }
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

sub apache_config {
  my $self = shift;

  my $r = $self->{request} or croak "no request object!?";
  if (MP2) {
    return Apache::Module::get_config(
      __PACKAGE__,
      $r->server,
      $r->per_dir_config,
    );
  } 
  return Apache::ModuleConfig->get($r);
}

sub handler ($$) {
  my($class, $r) = @_ > 1 ? @_ : (__PACKAGE__, shift());

  my $filename = $r->filename;
  *0 = \$filename;

  # Apache 2.x doesn't offer finfo()
  # $r->finfo; # Cached stat() structure
  -e $filename or return Apache::NOT_FOUND;
  return Apache::DECLINED if -d _;
  return Apache::FORBIDDEN unless -r _;

  # Support mod_perl 1.x Apache::Filter
  if (!MP2 and lc $r->dir_config('Filter') eq 'on') {
    $r = $r->filter_register;
  }

  $r->content_type('text/html; charset=ISO-8859-1');

  my $forge = $class->new(
    interpolate => 1,
    cache => 2,
    trim => 1,
  );
  $forge->{request} = $r;
  $forge->{status} = Apache::OK;
  
  my $cfg = MP2 
    ? Apache::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config) 
    : Apache::ModuleConfig->get($r);

  local @Text::Forge::FINC = @{ $cfg->{ForgeINC} || [] };
  local $Text::Forge::CACHE = $cfg->{ForgeCache};

  $forge->run($filename);
  return $forge->{status} if $forge->{status} != Apache::OK;

  $r->header_out('Content-Length', length $forge->{content});
  $r->send_http_header unless MP2;
  # docs say passing ref to print() is deprecated
  $r->print($forge->{content}) unless uc $r->method eq 'HEAD'; 

  return Apache::OK;
}

sub redirect {
  my $self = shift;
  my($url, $status) = @_;

  my $r = $self->{request};
  $r->content_type('text/html');
  $r->headers_out->{Location} = $url;
  $self->status($status || Apache::HTTP_MOVED_TEMPORARILY);
}

sub request {
  my $self = shift;

  $self->{request} = shift if @_;
  return $self->{request};
}

sub status {
  my $self = shift;

  $self->{status} = shift if @_;
  return $self->{status};
}

1;

__END__

=head1 NAME

Text::Forge::ModPerl - mod_perl handler

=head1 SYNOPSIS

  #### in httpd.conf
  PerlModule Text::Forge::ModPerl
  
  <FILES ~ "\.tf$">
    ForgeINC /usr/local/apache/templates
    ForgeCache On
    SetHandler perl-script
    PerlHandler +Text::Forge::ModPerl
  </FILES>

=head1 DESCRIPTION 

This module connects an Apache/mod_perl server to the Text::Forge
templating system.

=head2 APACHE DIRECTIVES 

=over 4

=item * ForgeINC

Where to look for templates to be included within other templates using
the C<< $forge->include() >> method. For example, this could point to a
directory that has a common header or footer. No default setting.

=item * ForgeCache

Weather or not to cache compiled templates. Not recommended for
development environments, where changes usually need to be made on the
fly. Default is C<On>.

=back

=head1 SUPPORT 

Please use the Text::Forge Sourceforge.net mailing list to discuss this
module. You can subscribe by sending an email to
text-forge-devel-subscribe@lists.sourceforge.net.

=head1 AUTHOR 

Original code by Maurice Aubrey <maurice@hevanet.com>. This document was
written by Adam Monsen <adamm@wazamatta.com>.

=head1 BUGS

Not tested with Apache/mod_perl 2.0 series.

=head1 SEE ALSO

Text::Forge(3), INSTALL guide packaged with Text::Forge, 
http://text-forge.sourceforge.net/

=cut
