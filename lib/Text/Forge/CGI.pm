package Text::Forge::CGI;

use strict;
use base qw/ Text::Forge /;

BEGIN {
  __PACKAGE__->mk_accessors(qw/ cgi /);
}

sub send_header {
  my $self = shift;

  return if $self->{header_sent}++;
  print $self->cgi->header;
}

sub initialize {
  my $self = shift;

  $self->SUPER::initialize;

  require CGI;
  $self->cgi(CGI->new);
}

1;
