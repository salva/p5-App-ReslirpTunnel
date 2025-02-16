use 5.038002;
use ExtUtils::MakeMaker;

WriteMakefile( NAME => 'App::SlirpTunnel',
               VERSION_FROM => 'lib/App/SlirpTunnel.pm',
               PREREQ_PM => { 'File::XDG' => '1.03',
                              'Log::Any' => '1.717',
                              'Net::OpenSSH' => '0.84',
                              'Path::Tiny' => '0.146',
                              'Data::Validate::Domain' => '0.15',
                              'Data::Validate::IP' => '0.31',
                            },
               ABSTRACT_FROM => 'lib/App/SlirpTunnel.pm',
               AUTHOR => 'Salvador Fandiño <sfandino@yahoo.com>',
               LICENSE => 'perl',
               EXE_FILES => ['bin/slirp-tunnel'],
);
