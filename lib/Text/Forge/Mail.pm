package Text::Forge::Mail;

our @MAILER = ();

use strict;
use base qw/ Mail::Send Text::Forge /;

sub mailer { 
  my $self = shift;
 
  $self->{mailer} = [ @_ ] if @_;
  return @{ $self->{mailer} || \@MAILER };
}

sub send {
  my $self = shift;

  my $mailer = $self->open($self->mailer);
  $mailer->print($self->trap_send(@_));
  $mailer->close;
}

=head1 NAME

Text::Forge::Mail - e-mail templating system

=head1 SYNOPSIS

  use Text::Forge::Mail;

  my $forge = Text::Forge::Mail->new;
  $forge->to('maurice@lovelyfilth.com');
  $forge->subject('Make Money Fast!!!!!');
  $forge->send('message.tf');

=head1 DESCRIPTION

This module sends templated e-mails.  It is a subclass of
the Mail::Send, which is itself a subclass of Mail::Mailer.

The mailer() method can be used to get/set the parameters that
are passed to the Mail::Mailer constructor.  This lets you
specify the mailer to use.  If you don't specify it, the class
will look around and use whatever mailer it finds.

  $forge->mailer('sendmail'); # explicit
  $forge->send('message.tf');

Alternatively, if you want to change the defaults, you
can override mailer() in a subclass or set the
@Text::Forge::Mail::MAILER global.

=head1 BUGS

The trap_send() method does not include the mail headers.

=head1 SEE ALSO

Text::Forge, Mail::Send, Mail::Mailer

=head1 AUTHORS

Maurice Aubrey <maurice@lovelyfilth.com>

=cut

1;
