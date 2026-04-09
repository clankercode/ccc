use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Call::Coding::Clis',
    VERSION_FROM  => 'lib/Call/Coding/Clis.pm',
    PREREQ_PM     => { 'File::Which' => 0 },
    EXE_FILES     => ['bin/ccc'],
    ABSTRACT      => 'Library and CLI for invoking coding assistants',
    LICENSE       => 'unlicense',
    MIN_PERL_VERSION => '5.010',
);
