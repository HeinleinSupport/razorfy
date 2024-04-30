requires 'IO::Socket::IP';
requires 'IO::Select';
requires 'Data::Dumper';
requires 'Razor2::Syslog';
requires 'Razor2::Client::Agent';

on 'develop' => sub {
    requires 'Term::ReadKey';
    requires 'Term::ReadLine::Gnu';
    requires 'Term::ReadLine::Perl';
};

