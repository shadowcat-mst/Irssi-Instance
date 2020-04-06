package Irssi::Instance::RemoteObject;

use Mojo::Base qw(Irssi::Instance::Base -signatures);

has 'socket_client';
has 'attrs';

sub get_attr ($self, $key) { $self->attrs->{$key} }

1;
