use ExtUtils::MakeMaker;
use 5.008;

WriteMakefile(
  'NAME' => 'Text::Forge',
  'VERSION_FROM' => 'lib/Text/Forge.pm', # finds $VERSION
  'PREREQ_PM' => {
    'File::Spec'            => 0,
    'HTML::Entities'        => 0,
    'URI::Escape'           => 0,
    'Class::Accessor::Fast' => 0,
    'Test::More'            => 0,
  },
  EXE_FILES  => [],
);

__END__
