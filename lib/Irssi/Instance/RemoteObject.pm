package Irssi::Instance::RemoteObject;

use Mojo::Base qw(Irssi::Instance::Base -signatures);

use overload
  '&{}' => sub { shift->get_attr_closure },
  fallback => 1;

has 'attrs';

sub get_attr_closure ($self) {
  sub ($key) { $self->get_attr($key) }
}

sub get_attr ($self, $key) { $self->attrs->{$key} }

1;
