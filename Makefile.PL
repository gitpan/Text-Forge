use ExtUtils::MakeMaker;

WriteMakefile(
  'NAME' => 'Text::Forge',
  'VERSION_FROM' => 'lib/Text/Forge.pm', # finds $VERSION
  'PREREQ_PM' => {
    'File::PathConvert'     => 0,
    'HTML::Entities'        => 0,
    'URI::Escape'           => 0,
    'Class::Accessor::Fast' => 0,
    'Test::More'            => 0,
  },

  'DIR' => [qw( mod_perl )],
);

__END__
