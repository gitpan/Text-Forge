package Text::Forge::CGI;

use strict;
use base qw/ Text::Forge /;

sub headers { 
  my $self = shift;

  require HTTP::Headers;
  $self->{headers} ||= HTTP::Headers->new;
}

sub cgi {
  my $self = shift;

  require CGI;
  $self->{cgi} ||= CGI->new;
}

sub send_header {
  my $self = shift;

  my $h = $self->headers;
  $h->content_length(length $self->{content});
  print $h->as_string, "\n";
}

sub run {
  my $self = shift;

  my $h = $self->headers;
  $h->content_type('text/html; charset=ISO-8859-1');

  $self->SUPER::run(@_);
}

sub redirect {
  my $self = shift;
  my $url = shift;
  my $status = shift || '302';

  $self->headers->header(
    Status => "$status Moved",
    Location => $url,
  );
}

1;
