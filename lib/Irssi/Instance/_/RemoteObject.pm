package Irssi::Instance::_::RemoteObject;

use Mojo::Base qw(Irssi::Instance::_::Base -signatures);

has 'conduit';
has 'attrs';

sub get_attr ($self, $key) { $self->attrs->{$key} }

1;
