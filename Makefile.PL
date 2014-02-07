use strict;
use warnings;
use ExtUtils::MakeMaker;

my $repo = 'https://github.com/benkasminbullock/WWW-Ideone';
my $issues = "$repo/issues";

WriteMakefile (
    NAME => 'WWW::Ideone',
    VERSION_FROM => 'lib/WWW/Ideone.pm',
    LICENSE => 'perl',
    AUTHOR => 'Ben Bullock <bkb@cpan.org>',
    ABSTRACT => 'Perl interface to ideone.com',
    PREREQ_PM => {
        Template => 0,
        'LWP::UserAgent' => 0,
        Carp => 0,
        'IO::Uncompress::Gunzip' => 0,
    },
    META_MERGE => {
        resources => {
            repository => $repo,
            bugtracker => $issues,
        },
    },
    MIN_PERL_VERSION => '5.008001',
);
