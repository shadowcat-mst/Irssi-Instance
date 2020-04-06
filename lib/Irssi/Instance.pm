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

1;
