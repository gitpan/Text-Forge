package Text::Forge::Sendmail;

$SENDMAIL_SEARCH = '/usr/sbin:/usr/lib:/usr/local/bin:/bin';
$SENDMAIL_PATH   = undef;

# use strict;
# use vars qw( @ISA $SENDMAIL_SEARCH $SENDMAIL_PATH );
use Carp;
use Symbol;
use Text::Forge;

@ISA = qw( Text::Forge );

sub new {
  my $class = shift;
  my %attr  = @_;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new( );

  $self->{autoload}{sendmail_path}   = 1;
  $self->{autoload}{queue}           = 1;
  $self->{autoload}{envelope_sender} = 1;      
  $self->{queue} = 0;
  
  @$self{ keys %attr } = values %attr;

  $self;
}          

sub _find_sendmail {
  my $self = shift;

  my @paths = split /:/, $SENDMAIL_SEARCH;
  foreach my $path (@paths) {
    return $self->{sendmail_path} = $SENDMAIL_PATH = "$path/sendmail"
      if -x "$path/sendmail";
  }
  return undef;
}

# currently, this always buffers
sub send { 
  my $self = shift;

  my $clone = $self->generate( @_ );

  my $sendmail = $clone->{sendmail_path} || $SENDMAIL_PATH ||
                 $clone->_find_sendmail or croak "unable to locate sendmail";

  my $envelope_sender = $clone->header('Envelope-Sender') ||
                        $clone->{envelope_sender};

  my @options = qw( -oi -t );
  push @options, '-odq' if $clone->{queue};
  push @options, "-f$envelope_sender" if $envelope_sender;    

  my $fh = gensym;
  open($fh, '|-') || exec($sendmail, @options) || croak "sendmail error: $!";
  print $fh $clone->as_string;
  close $fh or croak "sendmail error: $!";   

  $clone;
}           

sub as_string {
  my $self = shift;

  my @header = ();
  my %seen   = ();
  my %fields = ();
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
