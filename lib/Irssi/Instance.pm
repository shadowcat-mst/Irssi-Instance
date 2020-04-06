package Irssi::Instance;

use Irssi::Instance::_::Conduit;
use Import::Into;
use Mojo::Base qw(Irssi::Instance::_::Base -signatures -async_await);

has socket_path => sub { "$ENV{HOME}/.irssi.sock" };

has conduit => sub ($self) {
  Irssi::Instance::_::Conduit->new(
    socket_path => $self->socket_path,
  );
};

async sub start ($self) {
  await +(my $cn = $self->conduit)->start;
  await $cn->register_methods_for($self, undef);
}

1;
