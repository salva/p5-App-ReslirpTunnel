package App::SlirpTunnel;

our $VERSION = '0.01';

use strict;
use warnings;

use JSON;
use Socket;
use Data::Validate::Domain qw(is_hostname);

sub host_fqdn {
    my $host = shift;

    is_hostname($host)
        or die "Invalid hostname: $host\n";

    return $host if $host =~ /\.[^\.]+\.*$/;

    my ($err, @results) = getaddrinfo($host, undef);
    if ($err) {
        warn "Failed to resolve $host FQDN: $err\n";
        return;
    }

    foreach my $res (@results) {
        my ($fqdn, $addr) = ($res->{canonname}, $res->{addr});
        if (defined $fqdn) {
            warn "FQDN for $host is $fqdn\n";
            return $fqdn;
        }
    }
    warn "Could not determine FQDN for $host\n";
    return ();
}

sub win_resolve {
    my ($ssh, $host) = @_;

    is_hostname($host)
        or die "Invalid hostname: $host\n";

    my $out = $ssh->capture('powershell', '-Command', "Resolve-DnsName $host | ConvertTo-Json");
    warn "Resolve-DnsName output: $out\n";

    my $records = decode_json($out);
    for my $r (@$records) {
        if ($r->{Type} == 1) {
            my $addr = $r->{IP4Address};
            my $fqdn = $r->{Name};
            return ($fqdn, $addr);
        }
    }
    warn "Could not resolve $host in Windows remote host\n";
    return ()
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

App::SlirpTunnel - Perl extension for blah blah blah

=head1 SYNOPSIS

  use App::SlirpTunnel;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for App::SlirpTunnel, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Salvador Fandiño, E<lt>salva@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2025 by Salvador Fandiño

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.38.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
