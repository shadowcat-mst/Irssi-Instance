package Irssi::Instance;

use Irssi::Instance::_::Conduit;
use Irssi::Instance::_Do;
use Import::Into;
use Mojo::Base qw(-base -signatures -async_await);

sub import { Irssi::Instance::_Do->import::into(1) }

has socket_path => sub { "$ENV{HOME}/.irssi.sock" };

has conduit => sub ($self) {
  Irssi::Instance::_::Conduit->new(
    socket_path => $self->socket_path,
  );
};

async sub start ($self) {
  await $self->conduit->start;
  return $self;
}

1;
