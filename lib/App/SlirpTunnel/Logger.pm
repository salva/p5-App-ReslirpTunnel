package App::SlirpTunnel::Logger;

use strict;
use warnings;
use Path::Tiny;
use Log::Any;
use Carp qw(croak confess);

sub _init_logger {
    my ($self, %args) = @_;
    # warn "initializing logger for $self\n";
    eval {
        $self->{log_level} = my $level = $args{log_level} // 'warn';
        if ($args{log_to_stderr}) {
            $self->{log_to_stderr} = 1;
            $self->{log} = Log::Any->get_logger(default_adapter => ['Stderr', log_level => $level]);
        }
        else {
            $self->{log_to_stderr} = 0;
            my $fn = $self->{log_file} = $args{log_file} // "/tmp/slirp-tunnel.log";
            Path::Tiny->new($fn)->parent->mkdir;
            $self->{log} = Log::Any->get_logger(default_adapter => ['File', "$fn", log_level => $level]);
            if (defined $args{log_uid}) {
                chown $args{log_uid}, -1, $fn;
            }
            # warn "Sending log to $fn\n";
        }
        $self->{log_prefix} = $args{log_prefix} // 'SlirpTunnel';
    };
    if ($@) {
        warn "Can't initialize logger for $self, (uid: $<, euid: $>): $@\n";
        die $@;
    }
    # warn "logger initialized for $self: $self->{log}, level: $args{log_level}\n";
}

sub _log {
    my ($self, $level, @msg) = @_;
    local ($?, $@, $!);
    my $prefix = $self->{log_prefix} // 'SlirpTunnel';
    my $msg = "$prefix> ".join(': ', grep defined, @msg);
    eval {
        $self->{log}->$level($msg);
    };
    if ($@) {
        my $slots = join ', ', map { $_." => ".($self->{$_}//'<undef>') } keys %$self;
        confess "$msg  -- Can't log properly, $@\n$self: $slots\n";
    }
    return;
}

sub _die {
    my ($self, @msg) = @_;
    local ($?, $@, $!);
    my $msg = join(': ', grep defined, @msg);
    $self->_log(fatal => $msg);
    die "$msg\n";
}

1;
