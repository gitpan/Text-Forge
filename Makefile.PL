use ExtUtils::MakeMaker;

my %mm = (
           NAME         => 'Text::Forge',
           VERSION_FROM => 'Forge.pm',
           PREREQ_PM    => {
                             'HTTP::Headers'     => 0,
                             'HTTP::Response'    => 0,
                             'File::PathConvert' => 0,
                           },
           DIR          => [qw( )],
           dist         => {
                             COMPRESS => 'gzip -9f', SUFFIX => 'gz',
                             ZIP => '/usr/bin/zip', ZIPFLAGS => '-rl',   
                           }, 
         );

eval { require Apache::ModuleConfig };
if ($@) {
  print <<EOF;

### It doesn't look like you have mod_perl installed, so I'm
### going to skip installation of the Text::Forge::ModPerl class.

EOF
} else {
  $mm{DIR} = [qw( mod_perl )];
}

ExtUtils::MakeMaker::WriteMakefile( %mm );

