package Text::Forge;

use strict;
use Carp;
use File::Spec ();
use HTML::Entities ();
use URI::Escape ();

use base qw( Class::Accessor::Fast );

our $VERSION = '2.16';

our @FINC = ('.');
our %FINC;

our $STRICT = 1;

our $CACHE = 1;

our $NAMED_SUBS = 1;

our $DEBUG = 0;

our %OPS;
{

  my $code = sub { qq{ $_[0]; } };

  %OPS = (
    '$' => sub { 
      qq{ print $_[0]; }
    },
  
    '%'  => $code,
    " "  => $code,
    "\n" => $code,
    "\r" => $code,
    "\t" => $code,
  
    '=' => sub {
      # Call method as function -- faster
      qq{ print Text::Forge::escape_html(undef, $_[0]); } 
    },

    '?' => sub {
      # Call method as function -- faster
      qq{ print Text::Forge::escape_uri(undef, $_[0]); }
    },
  );

}

sub new {
  my $class = shift;
  
  $class = ref($class) || $class;
  bless {}, $class;
}

# We get a VERSION() from UNIVERSAL anyway
# sub version { $Text::Forge::VERSION }

sub find_template {
  my $self = shift;
  my $path = shift;

  foreach my $search (@Text::Forge::FINC, undef) {
    my $fpath = File::Spec->rel2abs($path, $search);
    return $fpath if $fpath and -e $fpath and ! -d _;
  }

  croak "Can't locate template '$path' in \@FINC (\@FINC contains: @FINC)";
}

# From Apache::Registry
# Assumes: $fpath is absolute, normalized path as returned 
# by find_part()
sub namespace {
  my $self = shift;
  my $fpath = shift;

  # Escape everything into valid perl identifiers
  $fpath =~ s/([^A-Za-z0-9_\/])/sprintf("_%02x", ord $1)/eg;

  # second pass cares for slashes and words starting with a digit
  $fpath =~
    s{ (/+)(\d?) }
     { '::' . (length $2 ? sprintf("_%02x", ord $2) : '') }egx;

  return "TF$fpath";
}

# This parsing technique is discussed in perlop
sub parse {
  my $class = shift;
  local $_ = shift;

  s/^#![^\n]*\n//; # remove shebang line, if present
 
  my @code;
  my $line = 0;
  LOOP: {
    # Match token
    if (/\G<%(.)(.*?)%>([ \t\r\f]*\n)?/sgc) {
      exists $OPS{ $1 } or die "unknown forge token '$1' at line $line\n";

      # If the op is a linefeed we have to keep it to get the line numbers right
      push @code, $OPS{'%'}->($1) if $1 eq "\n";

      push @code, $OPS{ $1 }->($2);
      push @code, $OPS{'%'}->($3) if length $3; # maintain line numbers 
      $line += do { my $m = "$1$2" . (defined $3 ? $3 : ''); $m =~ tr/\n/\n/ };
      redo LOOP;
    }

    # Match anything up to the beginning of a token
    if (/\G(.+?)(?=<%)/sgc) {
      my $str = $1;
      $str =~ s/((?:\\.)|(?:\|))/$1 eq '|' ? '\\|' : $1/eg;
      push @code, $OPS{'$'}->("qq|$str|");
      $line += do { my $m = $1; $m =~ tr/\n/\n/ };
      redo LOOP;
    }

    my $str = substr $_, pos;
    $str =~ s/((?:\\.)|(?:\|))/$1 eq '|' ? '\\|' : $1/eg;
    push @code, $OPS{'$'}->("qq|$str|") if length $str;
  }

  return join '', @code;
}

sub named_sub {
  my($self, $package, $path, $code) = @_;

  return join '',
    "package $package;\n\n",
    ($STRICT ? "use strict;\n\n" : "no strict;\n\n"),
    "sub run {\n",
    "  my \$forge = shift;\n",
    qq{\n# line 1 "$path"\n},
    "  $code",
    "\n}\n",
    "\\&run;", # return reference to sub
  ;  
}

sub anon_sub {
  my($self, $package, $path, $code) = @_;

  return join '',
    "return sub {\n",
    "  package $package;\n",
    ($STRICT ? "use strict;\n\n" : "no strict;\n\n"),
    "  my \$forge = shift;\n\n",
    qq{# line 1 "$path"\n},
    "  $code",
    "\n}\n",
  ;
}

# we isolate this to prevent closures in the new sub
# is there a better way?
sub mksub { eval $_[0] }

sub compile {
  my($self, $path) = @_;

  warn "DEBUG ", __PACKAGE__, " [$$] compiling $path\n" if $DEBUG;

  if (ref $path eq 'SCALAR') { # inline template?
    my $package = $self->namespace($path);
    my $code = $self->parse($$path);
    $code = $self->anon_sub($package, $path, $code);
    my $sub = Text::Forge::mksub($code);
    croak "compilation of forge template '$path' failed: $@" if $@;

    # XXX Should we clear the cache if it becomes too large?
    $FINC{ $path } = $sub if $CACHE;
    return $sub;
  }

  my $fpath = $self->find_template($path);
  my $package = $self->namespace($fpath);
  open my $fh, '<', $fpath or croak "unable to read '$fpath': $!";
  my $source = do { local $/; <$fh> };
  my $code = $self->parse($source);

  if ($NAMED_SUBS) {
    $code = $self->named_sub($package, $fpath, $code);
  } else {
    $code = $self->anon_sub($package, $fpath, $code);
  }

  #warn "CODE\n#########################\n$code\n############################\n";
  my $sub = Text::Forge::mksub($code);
  croak "compilation of forge template '$fpath' failed: $@" if $@;

  $FINC{ $path } = $sub if $CACHE;
  return $sub;
}

sub initialize {
  my $self = shift;

  delete $self->{content};
  $self->{header_sent} = 0;
}

sub include {
  my $self = shift;
  my $path = shift;

  delete $FINC{ $path } unless $CACHE;
  my $sub = $FINC{ $path } || $self->compile($path);
 
  $sub->($self, @_); 
}

sub send_header {
  my $self = shift;

  return if $self->{header_sent}++;
  # print "Content-type: text/html\n\n";
}

sub content { shift()->{content} }

sub trap_send {
  my $self = shift;

  $self->initialize;

  my $next = tied *STDOUT;
  tie *STDOUT, 'Text::Forge', $self;

  eval {
    $self->include(@_);
    $self->send_header unless $self->{header_sent};
  };
  my $errmsg = $@; # save $@ since retie could involve eval

  untie *STDOUT;
  tie *STDOUT, ref $next, $next if $next;

  die $errmsg if $errmsg;

  return $self->{content} if defined wantarray;
}

sub send {
  my $self = shift;

  my $stime = time;
  $self->trap_send(@_);
  print $self->{content};
}

sub escape_uri {
  my $class = shift;
  my @str = @_;
  local $_;

  foreach (@str) {
    s/([^-A-Za-z0-9_.])/$URI::Escape::escapes{ $1 }/g;
    # s/ /+/g;
  }
  return (wantarray ? @str : $str[0]);
}

sub escape_html {
  my $class = shift;
  my @str = @_;
  local $_;
 
  foreach (@str) {
    s/([^\n\t !\#\$%(-;=?-~])/$HTML::Entities::char2entity{ $1 }/g;
  }
  return (wantarray ? @str : $str[0]);
}

sub TIEHANDLE { $_[1] }
 
sub WRITE { croak 'write not implemented!' }
  
sub PRINT {
  my $self = shift;

  $self->send_header unless $self->{header_sent};
  $self->{content} .= join '', @_;
}
 
sub PRINTF {
  my $self = shift;

  $self->send_header unless $self->{header_sent};
  $self->{content} .= sprintf shift, @_;
}

sub UNTIE {}

=head1 NAME

Text::Forge - templating system

=head1 SYNOPSIS

  use Text::Forge;

  my $forge = Text::Forge->new;
  $forge->send('/path/to/template');

=head1 DESCRIPTION 

This module uses templates to create dynamic documents.
Templates are normal text files except they have a bit
of special syntax that allows you to run perl code inside
them.

Templating systems are most often used to create dynamic web
pages, but can be used for anything.

Text::Forge has the following goals:

=over 4

=item 1. Simplicity

The template syntax is minimalistic, consistent, and easy
to understand. The entire system is just a few hundred lines
of code.

=item 2. Familiarity

We use standard perl syntax wherever possible.  There is no
mini language to learn.

=item 3. Efficiency

We support real-world, high traffic sites.
Version 1.x has run Classmates.com for several years.

=item 4. Extendability

OO design that can easily be subclassed and customized.

=item 5. Specificity

It's a templating system, not a monolithic, all-encompassing
framework.  Everything that can be delegated to other modules, is.

=back

=head1 Template Syntax

Templates are normal text files except for blocks which look like
this:

  <% %>

The type of block is determined by the character that follows the
opening characters:

  <%% %> code block 
  <%  %> also a code block (any whitespace character)
  <%$ %> interpolate string
  <%= %> interpolate HTML escaped string
  <%? %> interpolate URI escaped string

All blocks are evaluated within the same lexical scope (so my
variables declared in one block are visible in subsequent blocks).

Templates are produced on standard output (there is a trap_send() method
that let's you capture the output).

Code blocks contain straight perl code.  Anything printed to standard output
becomes part of the template output.

The string interpolation block evaluates its contents and inserts the result
into the template.

The HTML escape block also does interpolation except the result is HTML escaped
first.  This is used heavily in web pages to prevent cross-site scripting
vulnerabilities.

The URI escape block also does interpolation except the result is URI escaped
first.  You can use this to interpolate values within query strings, for example.
Note that there's no need to HTML escape the result of this (the URI escaping
also escapes all unsafe HTML characters).

Parts of the template that are outside a block are treated like a
double-quoted string in Perl.  Which means you can interpolate variables directly
into the text if you like (although no escaping happens in this case, of course).

If a block is followed solely by whitespace up to the next newline, that whitespace
(including the newline) will be suppressed from the output.  If you really wanted
a newline, just add another newline after the block.  The idea here is that the
blocks themselves shouldn't affect the formatting.

=head1 Generating Templates

To generate a template, you need to instantiate a Text::Forge object and
tell it the template file to send:

  my $tf = Text::Forge->new;
  $tf->send('my_template');

Every template has access to a $forge object that provides some helpful methods
and can be used to pass information around.  Really, the $forge object is nothing
more than a reference to the Text::Forge object being used to construct the
template itself.

So, for example, assume that the 'my_template' file contains this:

  <%
     # this is start of code block
     $forge->send_header;
  %>
  Hello World!

$forge is just a reference to the $tf object.  The send_header() method
is usually called implicitly when the first byte of output is seen, but
here we're calling it explicitly for some unknown reason.

Since the Text::Forge class is subclassible, this mechanism makes
it simple to provide a consistent context to all your templates.  Suppose
that you're making web pages and you want to use the CGI.pm module
for handling form data.  Subclass Text::Forge and add a cgi() method that returns
the CGI.pm object.  Now, every template can grab the CGI.pm object by calling
$forge->cgi.  

You can include a template within another template using the include() method.
Here's how we might include a header in our main template.

  <% $forge->include('header') %>

Templates are really just Perl subroutines, so you can pass values into
them and they can pass values back.

  <% my $rv = $forge->include('header', title => 'foo', meta => 'blurgle' ) %>

The send() method generates the template on standard output.  If you want to
capture the output in a variable, use the trap_send() method instead.

  my $tf = Text::Forge->new;
  my $doc = $tf->trap_send('my_template');

You can generate a template that's in a scalar (instead of an external file)
by passing a reference to it.

  my $tf = Text::Forge->new;
  $tf->send(\"Hello Word <%= scalar localtime %>");

=head1 Error Handling

Exceptions are raised on error.  We take pains to make sure the line numbers
reported in errors and warnings match the line numbers in the templates themselves.

=head1 AUTHOR 

Support is available through the Text::Forge source-forge site at
http://text-forge.sourceforge.net/

Original code by Maurice Aubrey <maurice@hevanet.com>.
Please use the source-forge mailing list to discuss this module.

=cut

1;
