package Text::Forge;

$Debug = 0;

use strict;
use vars qw( 
              $VERSION $AUTOLOAD $CWD %URI_ESCAPES %HTML_ENTITIES $Debug 
           );
use Carp;
use Symbol qw();
use Cwd;
use HTTP::Headers;
use File::PathConvert;
use Text::Forge::MemCache;

$VERSION = '0.26';

$CWD = Cwd::fastcwd();

# Build mappings from URI and HTML encodings
# Taken from URI::Escape and HTML::Entities
for (0..255) {
  $URI_ESCAPES{ chr $_ } = sprintf('%%%02X', $_);
  $HTML_ENTITIES{ chr $_ } = "&#$_;";
}                          

sub new {
  my $class = shift;
  my %attr  = @_;

  $class = ref $class || $class;
  bless my $self = {}, $class;

  $self->initialize;
  @$self{ keys %attr } = values %attr;

  $self;  
}

sub initialize {
  my $self = shift;

  $self->{template_path} = $CWD;
  $self->{'header'}      = new HTTP::Headers; 
  $self->{buffer}        = 0;
  $self->{content}       = '';
  $self->{cache_module}  = 'Text::Forge::MemCache';

  $self->{autoload}      = { 
                             template_path => 1,
                             'header'      => 1,
                             buffer        => 1,
                             content       => 1,
                             cache_module  => 1,
                           };

  $self->{ops}           = {
                             '%'  => \&Text::Forge::_op_perl,
                             ' '  => \&Text::Forge::_op_perl,
                             "\n" => \&Text::Forge::_op_perl,
                             '$'  => \&Text::Forge::_op_interp,
                             '='  => \&Text::Forge::_op_html_encode,
                             '?'  => \&Text::Forge::_op_uri_escape,
                           };
}

sub version { $VERSION }

# Perform a deep copy of ourself.
# Note that this only works for one level.  
sub clone {
  my $self = shift;
  my %attr = @_;

  my $clone = $self->new;
  $clone->{'header'} = $self->{'header'}->clone;
  
  foreach my $key (keys %$self) {
    next if $key eq 'header';
    my $ref = ref $self->{ $key };
    $clone->{ $key } = { %{ $self->{ $key } } }, next if $ref eq 'HASH';
    $clone->{ $key } = [ @{ $self->{ $key } } ], next if $ref eq 'ARRAY';
    $clone->{ $key } = $self->{ $key }; 
  }
 
  @$clone{ keys %attr } = values %attr;
  $clone;  
}

# Construct a unique package name based on the template path.
# Based on Apache::Registry
sub _package {
  my $self = shift;
  my $path = shift;

  $path =~ s/([^A-Za-z0-9\/])/sprintf('_%02x', ord $1)/eg;
  $path =~ s{ (/+)(\d?) }
            { '::' . (length $2 ? sprintf('_%02x', ord $2) : '') }egx;
  return "Text::Forge::Template$path";
}

# Parse the template and write the code
# Based on Apache::Cachet
sub _parse {
  my $self = shift;
  my $doc  = shift;
  my($pre, $post, $string, $op, @code);

  $pre  = $1 if $doc =~ s#^(.*)<\s*FORGE\s*>##si;
  $post = $1 if $doc =~ s#<\s*/\s*FORGE\s*>(.*)$##si;

  my @tokens = split /<%(.)(.*?)%>/s, $doc;
  while(@tokens) {
    $string = shift @tokens;
    if (length $string) {
      # Strip whitespace from end of tag -- we place the whitespace in 
      # a code segment, so errors still report the proper line numbers
      if ((@code or defined $pre) and $string =~ /^([ \t\r\f]*\n)(.*)$/s) {
        $string = $2;
        push(@code, $self->{ops}{'%'}->( $1 ));
      }     
      $string =~ s/((?:\\.)|(?:\|))/$1 eq '|' ? '\\|' : $1/eg;
      push(@code, qq(  print qq|$string|; )) if length $string; 
    } 
    last unless @tokens;
    ($op, $string) = (shift @tokens, shift @tokens);
    exists $self->{ops}{ $op } or croak "unknown op '$op'";
    push @code, $self->{ops}{ $op }->( $string );
  } 

  return( join('', @code), $pre, $post );
}

sub _build_code {
  my $self = shift;
  my($path, $package, $code, $pre, $post) = @_;

  local $^W = 0;

  join '',
    "sub {\n",
    "  no strict;\n",
    "  package $package;\n",
    "  my \$forge = shift;\n\n",
    "# line 1 $path\n",
    "$pre ; \$forge->_pre_template; ",
    $code,
    "$post ; }; "; 
}

# Last chance for initialization prior to main template body
sub _pre_template {
  my $self = shift;

  return if $self->{_header_sent} or $self->{_tie_obj};
  return $self->_tie_stdout if $self->{buffer};

  my $header = $self->{'header'}->as_string;
  print "$header\n" if $header;
  $self->{_header_sent} = 1;
}                   

# This is run after we've finished with the entire template 
sub _post_template {
  my $self = shift;

  return unless $self->{_tie_obj};

  $self->{content} = join '', @{ $self->{_tie_obj } };
  $self->_untie_stdout;
}                        

sub _tie_stdout {
  my $self = shift;

  return if $self->{_tie_obj}; # Already tied?
  $self->{_old_tie} = tied *STDOUT;
  $self->{_tie_obj} = tie *STDOUT, 'Text::Forge'
    or croak "unable to tie STDOUT: $!";
}

sub _untie_stdout {
  my $self = shift;

  return unless $self->{_tie_obj};
  undef $self->{_tie_obj};
  untie *STDOUT;
  tie *STDOUT, ref $self->{_old_tie} if $self->{_old_tie};
  undef $self->{_old_tie};
}                

# Eval the code and cache it for next time.
sub compile {
  my $self  = shift;
  my @paths = @_;
  my($sub, @subs);
  local $/;

  foreach my $path (@paths) {
    $path = "$self->{template_path}/$path" unless $path =~ m#^/#;
    File::PathConvert::regularize( $path ) # 19% faster when skipped 
      unless $self->{'cache_module'}->is_cached( $path ); 

    my $fh = Symbol::gensym;
    open $fh, $path or croak "unable to read '$path': $!";
    my $template = <$fh>;
    close $fh or croak "error closing '$path': $!";
    my $package = $self->_package( $path );
    my $code = $self->_build_code($path, $package, $self->_parse( $template ));
    print STDERR "\n--- Start Code $path ---\n\n$code",
                 "\n\n--- End Code $path ---\n\n" if $Debug;
    # Eval doesn't catch warnings, so we set up our own warn handler
    {
      my $warning = '';
      local $SIG{__WARN__} = sub { $warning .= shift() };
      $sub = eval $code;
      croak "$warning$@" if $warning or $@;
    }
    $self->{'cache_module'}->store( $path, $sub );
    push @subs, $sub;
  }

  return (wantarray ? @subs : $subs[0]);
}

# This should only be called from within a template
sub include {
  my $self = shift;
  my $path = shift;

  $path or croak 'no path specified';
  
  $path = "$self->{template_path}/$path" unless $path =~ m#^/#;
  File::PathConvert::regularize( $path ) # 19% faster when skipped
    unless $self->{'cache_module'}->is_cached( $path );

  my $sub = $self->{'cache_module'}->fetch( $path ) ||
            $self->compile( $path );

  return $sub->($self, @_);              
}

# Process the template but don't generate any output
sub generate {
  my $self = shift;
  my $path = shift;

  croak 'cannot call generate() or send() from within template'
    if $self->{_in_template};

  my $clone = $self->clone( _in_template      => 1,
                            _header_sent      => 0,
                             content          => '' );
  $clone->_tie_stdout; 
  $clone->include( $path, @_ );
  $clone->_post_template;

  return $clone;
}

# Just like generate() but we output the result
sub send {
  my $self = shift;
  my $path = shift;

  croak 'cannot call generate() or send() from within template'
    if $self->{_in_template};

  my $clone = $self->clone( _in_template      => 1,
                            _header_sent      => 0,
                             content          => '' );
  $clone->include( $path, @_ );
  $clone->_post_template;

  # Send the document if we haven't already
  unless ($clone->{_header_sent}) {
    my $header = $clone->{'header'}->as_string;
    print "$header\n" if $header;
    print $clone->{content};
  }   

  return $clone;
}

sub op_handler {
  my $self = shift;

  return keys %{ $self->{ops} } unless @_;

  my $op = shift;
  return $self->{ops}{ $op } unless @_;

  my $sub = shift;
  ref $sub eq 'CODE' or croak 'op handler must be code reference';
  $self->{ops}{ $op } = $sub;
}                 

sub header { 
  my $self = shift;

  return $self->{'header'} unless @_;
  if (ref $_[0] eq 'ARRAY') {
    $self->{'header'} = new HTTP::Headers;
    return (wantarray ? () : undef);    
  }
  $self->{'header'}->header( @_ );
}

sub as_string {
  my $self = shift;

  my $header = $self->{'header'}->as_string;
  $header .= "\n" if $header;
  return "$header$self->{content}";
}

sub _op_perl   { my $data = shift; qq( $data; )       }       
sub _op_interp { my $data = shift; qq( print $data; ) }

# Inline encoding to remove overhead of function call
sub _op_html_encode {
  my $data = shift;

  return qq( print map { my \$e = \$_; \$e =~ s{([^\\n\\t !#\$%'-;=?-~])}{\$Text::Forge::HTML_ENTITIES{ \$1 }}gx; \$e; } $data; );
}

# Inline escaping to remove overhead of function call
sub _op_uri_escape {
  my $data = shift;

  return qq( print map { my \$e = \$_; \$e =~ s/([^A-Za-z0-9])/\$Text::Forge::URI_ESCAPES{ \$1 }/g; \$e; } $data; );
}                 

# Convenience methods

sub uri_escape { 
  my $self   = shift;
  my @values = @_;
  local $_;

  foreach (@values) {
    s/([^A-Za-z0-9])/$Text::Forge::URI_ESCAPES{ $1 }/g;
  }
  return (wantarray ? @values : $values[0]);
}

sub encode_entities {
  my $self = shift;
  my @values = @_;
  local $_;

  foreach (@values) {
    s/([^\n\t !\#\$%\'-;=?-~])/$Text::Forge::HTML_ENTITIES{ $1 }/g;
  }
  return (wantarray ? @values : $values[0]);
}

sub AUTOLOAD {
  my $self = shift;
  my $type = ref($self) || croak "autoload: $self is not an object";
  my $name = $AUTOLOAD;

  $name =~ s/.*://;
  return if $name eq 'DESTROY';
  croak "unknown autoload name '$name'" unless exists $self->{autoload}{$name};
  return (@_ ? $self->{$name} = shift : $self->{$name});
}            

# The next few routines are used for tying stdout when buffering is on.

sub TIEHANDLE {
  my $class = shift;

  bless [], $class;
}

sub WRITE { croak 'write not implemented!' }

sub PRINT {
  my $self = shift;

  push @$self, @_;
}
                                   
sub PRINTF {
  my $self = shift;
  my $fmt  = shift;

  push @$self, sprintf($fmt, @_);
}

sub DESTROY {
  my $self = shift;

  $self->_untie_stdout if $self->{_tie_obj} and not $self->{_in_template};
}                  

1;

__END__

=head1 NAME

Text::Forge - 

=head1 SYNOPSIS

  use Text::Forge;

  my $forge = new Text::Forge;
  $forge->send('mytemplate.tf');

=head1 DESCRIPTION

=head2 TEMPLATE SYNTAX


=head1 AUTHOR

Copyright 1998-1999, Maurice Aubrey E<lt>maurice@hevanet.comE<gt>.
All rights reserved.
 
This module is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

Text::Forge::CGI, Text::Forge::Sendmail, Text::Forge::MemCache,
Text::Forge::NoCache

=cut
