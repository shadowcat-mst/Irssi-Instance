package Irssi::Instance;

use Irssi::Instance::_::Conduit;
use Irssi::Instance::_Do;
use Import::Into;
use Mojo::Base qw(-base -signatures -async_await);

sub lookup_via { undef }

sub import { Irssi::Instance::_Do->import::into(1) }

has socket_path => sub { "$ENV{HOME}/.irssi.sock" };

has conduit => sub ($self) {
  Irssi::Instance::_::Conduit->new(
    socket_path => $self->socket_path,
  );
};

async sub start ($self) {
  my $cn = $self->conduit;
  await $cn->start;
  await $cn->setup_package(ref $self);
  return $self;
}

1;
