package Text::Forge::CGI;

# use strict;
# use vars qw( @ISA );
use Carp;
use Text::Forge;

@ISA = qw( Text::Forge );

sub new {
  my $class = shift;
  local($_);

  $class = ref($class) || $class;
  my $self = $class->SUPER::new( @_ );
  $self->{'header'}->content_type('text/html');
  
  $self;
}            

sub _post_template {
  my $self = shift;

  $self->SUPER::_post_template;
  $self->{'header'}->content_length( length $self->{content} );
}

sub redirect {
  my $self = shift;
  my $url  = shift;

  # XXX Is this portable?
  $url ||= "http://$ENV{SERVER_NAME}:$ENV{SERVER_PORT}$ENV{REQUEST_URI}";

  if ($self->{_in_template}) {
    $self->{'header'}->header( Status   => '302 Moved',
                               Location => $url );
  } else {
    print "Location: $url\nStatus: 302 Moved\n\n";
  }
}               

1;

__END__

=head1 NAME

Text-Forge - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Text-Forge;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Text-Forge was created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head1 AUTHOR

A. U. Thor, a.u.thor@a.galaxy.far.far.away

=head1 SEE ALSO

perl(1).

=cut
