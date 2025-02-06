package App::SlirpTunnel;

our $VERSION = '0.01';

use 5.038002;
use strict;
use warnings;

use POSIX;
use Socket;
use IO::Socket::UNIX;
use File::Spec;
use App::SlirpTunnel::RPC;

sub hexdump { unpack "H*", $_[0] }


sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub start {
    shift->_start_slave();
}

sub _my_lib_path {
    my $my_path = File::Spec->rel2abs($INC{'App/SlirpTunnel.pm'});
    my @dirs = File::Spec->splitdir($my_path);
    warn "L->dirs: |$my_path| --> |".join("|", @dirs). "|\n";

    pop @dirs for (1..2);
        warn "L->dirs: |$my_path| --> |".join("|", @dirs). "|\n";
    return File::Spec->catdir(@dirs);
}

sub _start_slave {
    my $self = shift;

    socketpair(my $parent_socket, my $child_socket, AF_UNIX, SOCK_STREAM, 0)
        or die "Socket pair creation failed: $!";

    # Step 2: Fork the process
    my $pid = fork();
    if (defined $pid && $pid == 0) {
        # Child process
        close($parent_socket);
        POSIX::dup2(fileno($child_socket), 1) or die "dup2 failed: $!";
        my $lib_path = _my_lib_path();
        my @sudo_cmd = ("sudo", $^X, "-I".$lib_path, "-MApp::SlirpTunnel::ElevatedSlave", "-e", "App::SlirpTunnel::ElevatedSlave::start");
        warn "L->Exec: @sudo_cmd\n";
        # exec { "echo" } ("echo", @sudo_cmd);
        exec { $sudo_cmd[0] } @sudo_cmd
            or die "Exec failed: $!";
    }
    elsif (not defined $pid) {
        die "Fork failed: $!";
    }

    # Parent process
    close($child_socket);
    sleep(1);

    $self->{rpc} = App::SlirpTunnel::RPC->new($parent_socket);
}

sub _request {
    my ($self, $cmd, %args) = @_;
    $self->{rpc}->send_packet({cmd => $cmd, args => \%args});
    my $r = $self->{rpc}->recv_packet();
    if ($r->{status} eq 'bye') {
        $self->{rpc} = undef;
    }
    return $r
}

sub hello { shift->_request('hello') }

sub create_tap {
    my $self = shift;
    my $r = $self->_request('create_tap');
    my $device = $r->{device};

    warn "getting device $device";
    
    $r->{fd_follows} or die "Failed to setup tap";
    my $fd = $self->{rpc}->recv_fd();

    # reopen $tap_fd as a Perl file handle
    my $tap_fh = IO::Socket::UNIX->new_from_fd($fd, "r+")
        or die "Failed to create tap file handle: $!";
    return ($device, $tap_fh);
}

sub device_up {
    my ($self, $device) = @_;
    return $self->_request('device_up', device => $device);
}

sub device_addr_add {
    my ($self, $device, $addr, $mask) = @_;
    return $self->_request('device_addr_add', device => $device, addr => $addr, mask => $mask);
}

sub bye {
    my $self = shift;
    return $self->_request('bye');
}

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
