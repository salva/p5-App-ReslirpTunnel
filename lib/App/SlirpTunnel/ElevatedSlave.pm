package App::SlirpTunnel::ElevatedSlave;

use strict;
use warnings;

use POSIX;
use Fcntl qw(:mode);
use Socket;
use Socket::MsgHdr;
use IO::Socket::UNIX;
use App::SlirpTunnel::RPC;

use constant TUNSETIFF => 0x400454ca;  # Define constant for TUNSETIFF
use constant IFF_TAP   => 0x0002;
use constant IFF_NO_PI => 0x1000;

sub _create_tap {
    my $tap_device = "tap0";  # Name of the TAP interface

    sysopen(my $tap_fd, "/dev/net/tun", O_RDWR) or die "Cannot open /dev/net/tun: $!";

    my $ifr = pack("Z16 s", $tap_device, IFF_TAP | IFF_NO_PI);
    ioctl($tap_fd, TUNSETIFF, $ifr) or die "ioctl TUNSETIFF failed: $!";

    warn "Created TAP device: $tap_device\n";
    return ($tap_device, $tap_fd);
}

sub _create_tap__rpc {
    my $request = shift;
    my ($tap_device, $tap_fd) = _create_tap();
    {status => "ok", device => $tap_device, fd => $tap_fd }
}

sub _do_system {
    my $self = shift;
    system(@_) or return { status => "ok" };
    warn "Command '@_' failed, rc: ".($? >> 8)."\n";
    return { status => "error" };

}

sub _device_up__rpc {
    my ($self, $request) = @_;
    my $device = $request->{device};
    $self->_do_system("ip", "link", "set", "dev", $device, "up");
}

sub _device_addr_add__rpc {
    my ($self, $request) = @_;
    my $device = $request->{device};
    my $addr = $request->{addr};
    my $mask = $request->{mask};
    $self->_do_system("ip", "addr", "add", "$addr/$mask", "dev", $device);
}

sub _bye__rpc {
    return { status => "bye" }
}

sub _hello__rpc {
    return { status => "ok" }
}

sub _run {
    my $self = shift;

    while (1) {
        warn "Waiting for request\n";
        my $request = $self->{rpc}->recv_packet();

        my $cmd = $request->{cmd};

        my $method = "_${cmd}__rpc";
        my $r = $self->$method($request->{args} // {});
        my $fd = delete $r->{fd};
        if (defined $fd) {
            $r->{fd_follows} = 1;
        }
        $self->{rpc}->send_packet($r);
        if (defined $fd) {
            $self->{rpc}->send_fd($fd);
        }
        last if ($r->{status} eq 'bye')
    }
    warn "Bye bye!\n";
}

sub new {
    my ($class, $socket) = @_;
    my $rpc = App::SlirpTunnel::RPC->new($socket);
    my $self = { socket => $socket,
                 rpc => $rpc };
    bless $self, $class;
}

sub start {
    POSIX::dup2(1, 3);
    POSIX::dup2(2, 1);
    my $socket = IO::Socket::UNIX->new_from_fd(3, "r+")
        or die "Failed to create socket: $!";

    my $server = __PACKAGE__->new($socket);
    $server->_run();
}

1;
