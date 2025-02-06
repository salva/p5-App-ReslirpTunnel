
package App::SlirpTunnel::Butler;

use strict;
use warnings;

use POSIX;
use Socket;
use IO::Socket::UNIX;
use File::Spec;
use App::SlirpTunnel::RPC;

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

1;
