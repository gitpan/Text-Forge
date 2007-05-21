package Text::Forge;

use strict;
use Carp;
use File::Spec ();
use HTML::Entities ();
use URI::Escape ();

our $VERSION = '4.01';

our @FINC = ('.');

our %FINC;
our %ABS_PATH;

our $INTERPOLATE = 0;
our $TRIM = 0;
our $CACHE = 1;
our $NAMESPACE = 'TF'; # package that templates are compiled into

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
    ''   => $code,
    "\n" => $code,
    "\r" => $code,
    "\t" => $code,
  
    '=' => sub {
      qq{ print Text::Forge::Util::html_escape($_[0]); } 
    },

    '?' => sub {
      qq{ print Text::Forge::Util::url_encode($_[0]); }
    },

    '#' => sub { $_[0] =~ s/[^\r\n]//g; $_[0]; },
  );

}

BEGIN {
  package Text::Forge::Util;

  use strict;
  use HTML::Entities ();
  use URI::Escape ();

  sub html_escape {
    my @str = @_;
    local $_;

    foreach (@str) {
      s/([^\n\t !\#\$%(-;=?-~])/$HTML::Entities::char2entity{ $1 }/g;
    }
    return (wantarray ? @str : $str[0]);
  }
  *h = \&html_escape;

  sub url_encode {
    my @str = @_;
    local $_;
  
    foreach (@str) {
      s/([^-A-Za-z0-9_.])/$URI::Escape::escapes{ $1 }/g;
      # s/ /+/g;
    }
    return (wantarray ? @str : $str[0]);
  }
  *u = \&url_encode;

  # we isolate this to prevent closures in the new sub
  # is there a better way?
  sub mksub {
    no warnings 'redefine';
    eval $_[0] 
  }
}

sub new {
  my $class = shift;
  
  $class = ref($class) || $class;
  my $self = bless {}, $class;
  return $self->_initialize(@_);
}

sub _initialize {
  my $self = shift;

  my %args = (
    trim => $TRIM,
    interpolate => $INTERPOLATE,
    cache => $CACHE,
    @_
  );

  %$self = map { +"_tf_$_" => $args{$_} } keys %args;
  return $self;
}

sub namespace {
  my $class = shift;

  $NAMESPACE = shift if @_;
  return $NAMESPACE;
}

sub search_paths {
  my $class = shift;

  if (@_) {
    @FINC = @_;
    %ABS_PATH = (); # lookups may change
  }
  return @FINC if defined wantarray;
}

# From Apache::Registry
# Assumes: $path is absolute, normalized path
sub _path2pkg {
  my $self = shift;
  my $path = shift;

  $path = "/$path" if ref $path;

  # Escape everything into valid perl identifiers
  $path =~ s/([^A-Za-z0-9_\/])/sprintf("_%02x", ord $1)/eg;
  # second pass cares for slashes and words starting with a digit
  $path =~
    s{ (/+)(\d?) }
     { '::' . (length $2 ? sprintf("_%02x", ord $2) : '') }egx;

  return $self->namespace . $path;
}

my $ws = '\t\r\f ';
my $block_re = qr/
  \G
  ([ \t]*)             # optional leading whitespace
  <%(.?)(.*?)(?<!\\)%> # start of block
  ([$ws]*\n)?          # trailing whitespace up to newline
/xs;
my $not_block_re = qr/
  \G
  (.+?)                # match anything up to...
  (?=
    [$ws]*             # optional whitespace followed by 
    (((?<!\\)<%) | \z) # the next (unescaped) block or end of template
  )
/xs;

# This parsing technique is discussed in perlop
sub _parse {
  my $self = shift;
  local $_ = shift;

  no warnings 'uninitialized';

  my @code;
  my $line = 0;
  LOOP: {
    # Match token
    if (/$block_re/cg) { 
      my($lws, $op, $block, $rws) = ($1, $2, $3, $4);
      # warn "OP: '$op' BLOCK: '$block' RWS: '$rws'\n";
      my $rtrim = 0;
      $rtrim = substr $block, -1, 1, '' if $block =~ /-\z/;

      my $ltrim = 0;
      if ($op eq '-') {
        $ltrim = 1;
        $op = '%';
      }

      exists $OPS{ $op } or die "unknown forge op '$op' at line $line\n";

      if (length $lws and not $ltrim) {
        push @code, $OPS{'$'}->("qq|$lws|");
      }

      # If the op is a linefeed we have to keep it to get the line numbers right
      push @code, $OPS{'%'}->($op) if $op eq "\n";

      push @code, $OPS{ $op }->(map { s/\\%>/%>/g; $_ } "$block");
      if (length $rws) { # trailing whitespace
        # Always output as code to keep lines straight
        push @code, $OPS{'%'}->($rws);
        unless ($rtrim) {
          # We already output the newlines as code, so escape them
          # if we need to print too.
          my $str = $rws;
          $str =~ s/([\n\r\f])/sprintf "\\x{%04x}", ord($1)/ge;
          push @code, $OPS{'$'}->("\$forge->{_tf_trim} ? '' : qq|$str|");
        }
      }
      $line += do { my $m = "$block$rws"; $m =~ tr/\n/\n/ };
      redo LOOP;
    }

    # Match anything up to the beginning of a block 
    if (/$not_block_re/cg) {
      my $str = $1;
      $str =~ s/((?:\\.)|(?:\|))/$1 eq '|' ? '\\|' : $1/eg;
      push @code,
        $OPS{'$'}->("\$forge->{_tf_interpolate} ? qq|$str| : q|$str|");
      $line += do { my $m = $str; $m =~ tr/\n/\n/ };
      redo LOOP;
    }

    my $str = substr $_, pos;
    warn "Something's wrong" if length $str;
  }

  return join '', @code;
}

sub _named_sub {
  my($self, $package, $path, $code) = @_;

  return join '',
    "package $package;\n\nuse strict;\n\n",
    "*h = \\&Text::Forge::Util::html_escape;\n",
    "*u = \\&Text::Forge::Util::url_encode;\n",
    "sub run {\n",
    "  my \$forge = shift;\n",
    qq{\n# line 1 "$path"\n},
    "  $code",
    "\n}\n",
    "\\&run;", # return reference to sub
  ;  
}

sub _compile {
  my $self = shift;
  my $path = shift;

  my $code;
  if (ref $path eq 'SCALAR') { # inline template?
    $code = $self->_parse($$path);
  } else {
    open my $fh, '<', $path or croak "unable to read '$path': $!";
    my $source = do { local $/; <$fh> };
    $code = $self->_parse($source);
  }
  my $pkg = $self->_path2pkg($path);
  $code = $self->_named_sub($pkg, $path, $code);
  my $sub = Text::Forge::Util::mksub($code);
  croak "compilation of forge template '$path' failed: $@" if $@;

  #warn "CODE\n#########################\n$code\n############################\n";
  return $sub;
}

sub _find_template {
  my $class = shift;
  my $path = shift;

  if (File::Spec->file_name_is_absolute($path)) {
    return File::Spec->canonpath($path);
  }

  return $ABS_PATH{ $path } if $ABS_PATH{ $path };

  foreach my $base ($class->search_paths) {
    my $abs_path = File::Spec->rel2abs($path, $base) or next;
    return $ABS_PATH{ $path } = $abs_path if -f $abs_path;
  }

  croak "Can't locate template '$path' in \@FINC (\@FINC contains: @FINC)";
}

sub include {
  my $self = shift;
  my $path = shift;

  my $sub;
  unless ($sub = $self->{_tf_finc}{ $path }) { # instance cache
    my $is_ref = ref $path eq 'SCALAR';
    my $abs_path = $is_ref ? $path : $self->_find_template($path);

    my $mtime;
    if ($self->{_tf_cache} and $FINC{ $abs_path }) { # global cache
      if (not $is_ref and 1 == $self->{_tf_cache}) {
        $mtime = (stat($abs_path))[9];
        unless ($mtime and $FINC{ $abs_path }[1] == $mtime) {
          delete $FINC{ $abs_path };
        }
      }
      $sub = $FINC{ $abs_path }[0] if $FINC{ $abs_path };
    }

    unless ($sub) { # recompile
      $sub = $self->_compile($abs_path) or croak "no sub?!";
      if ($self->{_tf_cache}) {
        if (not $is_ref and 1 == $self->{_tf_cache}) {
          $mtime ||= (stat($abs_path))[9];
        }
        $FINC{ $abs_path } = [$sub, $mtime];
      }
    }

    $self->{_tf_finc}{ $path } = $sub;
  }

  $sub->($self, @_); 
}

sub content { $_[0]->{content} }

sub run {
  my $self = shift;

  $self->{content} = '';
  local *STDOUT;
  open STDOUT, '>', \$self->{content}
    or croak "can't redirect STDOUT to scalar: $!";
  $self->include(@_);

  return $self->{content} if defined wantarray;
}

# deprecated; use "print $forge->run('template')" instead
*trap_send = \&run;
sub send { 
  my $self = shift;

  print $self->run(@_)
}

sub url_encode { shift; Text::Forge::Util::url_encode(@_) }
*u = *escape_uri = \&url_encode;

sub html_escape { shift; Text::Forge::Util::html_escape(@_) }
*h = *escape_html = \&html_escape;

=head1 NAME

Text::Forge - ERB/PHP/ASP-style templating for Perl

=head1 SYNOPSIS

  use Text::Forge;
  my $forge = Text::Forge->new;

  # template in external file
  print $forge->run('/tmp/mytemplate');

  # inline template (scalar reference)
  print $forge->run(\"<h1>Hello, World! <%= scalar localtime %></h1>");

=head1 DESCRIPTION 

Text::Forge is a simple templating system that allows you to
embed Perl within plain text files. The syntax is very similar
to other popular systems like ERB, ASP, and PHP.

=head2 Template Syntax 

Templates are normal text files except for a few special tags:
 
  <% Perl code; nothing output %>
  <%= Perl expression; result is HTML encoded and output %>
  <%$ Perl expression; result is output (no encoding) %>
  <%? Perl expression; result is URL escaped and output %> 
  <%# Comment; entire block ignored %>

All blocks are evaluated within the same lexical scope (so my
variables declared in one block are visible in subsequent blocks).

If a block is followed by a newline and you want to suppress it,
add a minus to the close tag:

  <% ... -%>

=head2 Generating Templates

To generate a template, you need to instantiate a Text::Forge object and
tell it the template file to use:

  my $tf = Text::Forge->new;
  print $tf->run('my_template');

Every template has access to a $forge object that provides some helpful
methods and can be used to pass around context.  Really, the $forge
object is nothing more than a reference to the Text::Forge object being
used to construct the template itself.

You can include a template within another template using the include() method.
Here's how we might include a header in our main template.

  <% $forge->include('header') %>

Templates are really just Perl subroutines, so you can pass values into
them and they can pass values back.

  <% my $rv = $forge->include('header', title => 'foo', meta => 'blurgle' ) %>

You can generate a template from a scalar (instead of an external file)
by passing a reference to it.

  my $tf = Text::Forge->new;
  $tf->send(\"Hello Word <%= scalar localtime %>");

=head2 Caching 

By default, templates are compiled, cached in memory, and are only recompiled
if they change on disk. You can control this through the constructor:

  my $forge->new(cache => 2)

Valid cache values are:

  0 - always recompile
  1 - recompile if modified
  2 - never recompile

=head2 Search Paths

If a relative path is passed to the run() method, it is searched for
within a list of paths. You can adjust the search paths through
the search_paths() class method:

  Text::Forge->search_paths('.', '/tmp');

By default, the search path is just the current directory, '.'

=head2 Error Handling

Exceptions are raised on error.  We take pains to make sure the line numbers
reported in errors and warnings match the line numbers in the templates themselves.

=head2 Other Constructor Options

  # Automatically trim trailing newlines from all blocks.
  my $forge = Text::Forge->new(trim => 1);

  # Interpolate variables outside template blocks (treats the
  # whole template as a double quoted string). Not recommended.
  my $forge = Text::Forge->new(interpolate => 1);

=head1 AUTHOR 

Copyright 1999-2007, Maurice Aubrey <maurice@hevanet.com>.
All rights reserved.

This module is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut

1;
