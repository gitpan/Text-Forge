package Text::Forge::SMTP;

use strict;
use vars qw( @ISA );
use Carp;
use Symbol;
use Net::SMTP;
use Text::Forge;

@ISA = qw( Text::Forge );

sub new {
  my $class = shift;
  my %attr  = @_;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new( );

  $self->{autoload}{host}            = 1;
  $self->{autoload}{envelope_sender} = 1;      
  $self->{autoload}{timeout}         = 1;
  $self->{autoload}{hello}           = 1;
  $self->{host}                      = undef;
  $self->{timeout}                   = undef;
  $self->{hello}                     = undef;
  $self->{smtp}                      = {};
  
  @$self{ keys %attr } = values %attr;

  $self;
}          

sub _smtp_croak {
  my $self = shift;
  my($msg, $smtp) = @_;

  my $smtp_msg = (defined $smtp  
                    ? join '', "[", $smtp->code, "] ", $smtp->message
                    : "SMTP object undefined"); 
  croak "$msg: $smtp_msg";
}

sub connect {
  my $self  = shift;
  my @hosts = @_;

  push @hosts, $self->{host} unless @hosts;
  my @smtp;
  foreach my $host (@hosts) {
    if (exists $self->{smtp}{ $host }) {
      eval { $self->disconnect( $host ) };
    }
    my $smtp = new Net::SMTP( $host, Hello => $self->{hello},
                              Timeout  => $self->{timeout} ) 
      or croak "unable to connect to '$host': $@";
    $self->{smtp}{ $host } = $smtp;
    push @smtp, $smtp;
  }
  return (wantarray ? @smtp : $smtp[0]);
}

sub disconnect {
  my $self  = shift;
  my @hosts = @_;

  push @hosts, $self->{host} unless @hosts;

  foreach my $host (@hosts) {
    next unless my $smtp = $self->{smtp}{ $host };
    $smtp->quit 
      or $self->_smtp_croak("unable to disconnect from '$host'", $smtp);
    delete $self->{smtp}{ $host };
  }
}                     

sub disconnect_all {
  my $self = shift;

  foreach my $host (keys %{ $self->{smtp} }) {
    $self->disconnect( $host );
  }
}

sub fetch_connection {
  my $self = shift;

  $self->{smtp}{ shift || $self->{host} };
}

sub is_connected {
  my $self = shift;
  my $host = shift || $self->{host};

  return undef 
    unless ref $self->{smtp}{ $host } and $self->{smtp}{ $host }->connected;
  return 1;
}

# currently, this always buffers
sub send { 
  my $self = shift;

  my $clone = $self->generate( @_ );

  my $no_disconnect = $clone->is_connected;
  my $smtp = $clone->fetch_connection || $clone->connect;

  my $from = $clone->header('Envelope-Sender') ||
             $clone->{envelope_sender} || $clone->header('From'); 
  my @rcpt = $clone->header('To');
  push @rcpt, $clone->header('Cc');
  push @rcpt, $clone->header('Bcc');

  $smtp->mail( $from ) or $self->_smtp_croak('error sending MAIL FROM', $smtp);
  $smtp->to( @rcpt ) or $self->_smtp_croak('error sending RCPT TO', $smtp);
  $smtp->data( $clone->as_string ) 
    or $self->_smtp_croak('error sending DATA', $smtp);

  $clone->disconnect unless $no_disconnect;

  $clone;
}           

sub as_string {
  my $self = shift;

  my @header = ();
  my %seen   = ();
  my %fields = ();
  $self->{'header'}->remove_header('Bcc');
  $self->{'header'}->scan( sub { $fields{ $_[0] } = 1 } );

  foreach my $field (keys %fields) {
    next if $field =~ /^Envelope-Sender$/i;
    push @header, "$field: " . join(', ', $self->header( $field ));
  }    

  return join '', join("\n", @header), "\n\n$self->{content}";
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
