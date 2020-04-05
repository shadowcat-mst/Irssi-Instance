package Irssi::Instance::_::Object;

use Mojo::Base qw(-base -signatures);

has 'conduit';
has lookup_via => sub { die "Can't call object without lookup_via" };
has 'attrs';

sub get ($self, $key) { $self->attrs->{$key} }

1;
