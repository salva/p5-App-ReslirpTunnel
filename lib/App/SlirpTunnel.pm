package App::SlirpTunnel;

our $VERSION = '0.01';

use strict;
use warnings;

sub hexdump { unpack "H*", $_[0] }

sub loop {
    my ($tap_handle, $ssh_handle) = @_;

    my $tap2ssh_buff = '';
    my $ssh2tap_buff = '';
    my $pkt_buff;
    my $max_buff_size = 65*1025;  # 10KB buffer

    my $tap_fd = fileno($tap_handle);
    my $ssh_fd = fileno($ssh_handle);

    while (1) {
        my $rfds = '';
        my $wfds = '';
        my $efds = $rfds;

        vec($rfds, $ssh_fd, 1) = 1 if length($ssh2tap_buff) < $max_buff_size;
        vec($rfds, $tap_fd, 1) = 1 if length($tap2ssh_buff) < $max_buff_size;

        my $ssh2tap_pkt_len;
        if (length($ssh2tap_buff) >= 2) {
            $ssh2tap_pkt_len = unpack("n", $ssh2tap_buff);
            if (length($ssh2tap_buff) >= $ssh2tap_pkt_len + 2) {
                vec($wfds, $tap_fd, 1) = 1;
            }
        }
        if (length($tap2ssh_buff) > 0) {
            vec($wfds, $ssh_fd, 1) = 1;
        }
        # warn "L->tap_fd: $tap_fd, ssh_fd: $ssh_fd\n";
        #warn "L->Before select, rfds: |".hexdump($rfds)."|, wfds: |".hexdump($wfds)."|\n";

        my $nfound = select($rfds, $wfds, $efds, 1);
        do {
            local $!;
            warn "L->After select, rfds: |".hexdump($rfds)."|, wfds: |".hexdump($wfds)."|, efds: |".hexdump($efds)."| nfound: $nfound, \$!: >$!<\n";
        };

        if ($nfound <= 0) {
            warn "L->select failed ($nfound): $!";
            next;
        }

        if (vec($rfds, $ssh_fd, 1)) {
            warn "L->can read from ssh\n";
            my $n = sysread($ssh_handle, $ssh2tap_buff, $max_buff_size, length($ssh2tap_buff));
            if (!defined $n) {
                warn "L->Read from SSH failed: $!";
            }
            elsif ($n == 0) {
                # die "SSH closed connection";
                warn "SSH closed connection";
            }
            else {
                warn "L->Read packet from ssh, length: $n\n";
                if (length($ssh2tap_buff) >= 2) {
                    my $ssh2tap_pkt_len = unpack("n", $ssh2tap_buff);
                    warn "L->Packet length: $ssh2tap_pkt_len, available: ".length($ssh2tap_buff)."\n";
                }
            }
        }
        if (vec($rfds, $tap_fd, 1)) {
            warn "L->can read from tap\n";
            my $n = sysread($tap_handle, $pkt_buff, $max_buff_size);
            if (!defined $n) {
                warn "L->Read from TAP failed: $!";
            }
            elsif ($n == 0) {
                die "TAP closed connection";
            }
            else {
                warn "L->Read packet from tap, length: $n\n";
                $tap2ssh_buff .= pack("n", $n) . $pkt_buff;
            }
        }
        if (vec($wfds, $ssh_fd, 1)) {
            warn "L->can write to ssh\n";
            my $n = syswrite($ssh_handle, $tap2ssh_buff, length($tap2ssh_buff));
            if (!defined $n) {
                warn "L->Write to SSH failed: $!";
            }
            elsif ($n == 0) {
                die "SSH closed connection";
            }
            else {
                warn "L->Write to SSH: $n\n";
                substr($tap2ssh_buff, 0, $n) = '';
            }
        }
        if(vec($wfds, $tap_fd, 1)) {
            warn "L->can write to tap\n";
            if (not defined $ssh2tap_pkt_len or length($ssh2tap_buff) < $ssh2tap_pkt_len + 2) {
                warn "L->Unexpected write flag for TAP";
            }
            else {
                my $n = syswrite($tap_handle, substr($ssh2tap_buff, 2, $ssh2tap_pkt_len));
                # In any case, we remove the packet from the buffer. The TCP/IP magic!
                substr($ssh2tap_buff, 0, $ssh2tap_pkt_len + 2) = '';
                if (!defined $n) {
                    warn "L->Write to TAP failed: $!";
                }
                elsif ($n == 0) {
                    die "Write to TAP failed: $!";
                }
            }
        }
    }
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
