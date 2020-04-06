package Irssi::Instance;

use Irssi::Instance::SocketClient;
use Import::Into;
use Mojo::Base qw(Irssi::Instance::Base -signatures -async_await);

has socket_path => sub { "$ENV{HOME}/.irssi.sock" };

has socket_client => sub ($self) {
  Irssi::Instance::SocketClient->new(
    socket_path => $self->socket_path,
  );
};

async sub start ($self) {
  await +(my $cn = $self->socket_client)->start;
  await $cn->register_methods_for($self, undef);
}

sub await ($, $p) {
  die "Irssi::Instance await method only valid at top level.\n"
    if $p->ioloop->is_running;
  my (@result, $err) = @_;
  $p->then(sub { @result = @_ }, sub { ($err) = @_ })->wait;
  die $err if $err;
  return wantarray ? $result[0] : @result;
}

1;
