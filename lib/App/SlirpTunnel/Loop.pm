package App::SlirpTunnel::Loop;

use strict;
use warnings;

use parent 'App::SlirpTunnel::Logger';

sub new {
    my ($class, %logger_args) = @_;
    my $self = bless {}, $class;
    $self->_init_logger(%logger_args,
                       log_prefix => 'SlirpTunnel::Loop');
    return $self;
}

sub hexdump { unpack "H*", $_[0] }

sub run {
    my ($self, $tap_handle, $ssh_handle, $ssh_err_handle) = @_;

    my $tap2ssh_buff = '';
    my $ssh2tap_buff = '';
    my $err_buff = '';
    my $pkt_buff;
    my $max_buff_size = 65*1025;  # 10KB buffer

    my $tap_fd = fileno($tap_handle);
    my $ssh_fd = fileno($ssh_handle);
    my $err_fd = fileno($ssh_err_handle);

    while (1) {
        my $rfds = '';
        my $wfds = '';
        my $efds = $rfds;

        vec($rfds, $ssh_fd, 1) = 1 if length($ssh2tap_buff) < $max_buff_size;
        vec($rfds, $tap_fd, 1) = 1 if length($tap2ssh_buff) < $max_buff_size;
        vec($rfds, $err_fd, 1) = 1;

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

        my $nfound = select($rfds, $wfds, $efds, 15);
        do {
            local $!;
        };

        if ($nfound <= 0) {
            next;
        }

        if (vec($rfds, $ssh_fd, 1)) {
            my $n = sysread($ssh_handle, $ssh2tap_buff, $max_buff_size, length($ssh2tap_buff));
            if (!defined $n) {
                $self->_log(warn => "Read from SSH failed", $!);
            }
            elsif ($n == 0) {
                $self->_log(warn => "SSH closed connection");
                # TODO: handle this!
            }
        }
        if (vec($rfds, $tap_fd, 1)) {
            my $n = sysread($tap_handle, $pkt_buff, $max_buff_size);
            if (!defined $n) {
                $self->_log(warn => "Read from TAP failed", $!);
            }
            elsif ($n == 0) {
                $self->_log(warn => "TAP closed connection");
                # TODO: handle this!
            }
            else {
                $tap2ssh_buff .= pack("n", $n) . $pkt_buff;
            }
        }
        if (vec($wfds, $ssh_fd, 1)) {
            my $n = syswrite($ssh_handle, $tap2ssh_buff, length($tap2ssh_buff));
            if (!defined $n) {
                $self->_log(warn => "Write to SSH failed", $!);
            }
            elsif ($n == 0) {
                $self->_log(warn => "SSH closed connection");
                die "SSH closed connection";
            }
            else {
                substr($tap2ssh_buff, 0, $n) = '';
            }
        }
        if(vec($wfds, $tap_fd, 1)) {
            if (not defined $ssh2tap_pkt_len or length($ssh2tap_buff) < $ssh2tap_pkt_len + 2) {
                $self->_log(warn => "Unexpected write flag for TAP");
            }
            else {
                my $n = syswrite($tap_handle, substr($ssh2tap_buff, 2, $ssh2tap_pkt_len));
                # In any case, we remove the packet from the buffer. The TCP/IP magic!
                substr($ssh2tap_buff, 0, $ssh2tap_pkt_len + 2) = '';
                if (!defined $n) {
                    $self->_log(warn => "Write to TAP failed", $!);
                }
                elsif ($n == 0) {
                    $self->_log(warn => "TAP closed", $!);
                    die "TAP closed";
                }
            }
        }
        if (vec($rfds, $err_fd, 1)) {
            my $n = sysread($ssh_err_handle, $err_buff, $max_buff_size, length($err_buff));
            if (!defined $n) {
                $self->_log(warn => "Read from SSH error channel failed", $!);
            }
            elsif ($n == 0) {
                $self->_log(warn => "SSH error channel closed");
                die "SSH error channel closed";
            }
            else {
                while ($err_buff =~ s/^(.*)\n//) {
                    next if $1 =~ /^\s*$/;
                    $self->_log(info => "Remote stderr", $1);
                }
                while (length($err_buff) >= 1500) {
                    $self->_log(ingo => "Remote stderr", substr($err_buff, 0, 1500)." (truncated)");
                    substr($err_buff, 0, 1500) = '';
                }
            }
        }
    }
}

1;
