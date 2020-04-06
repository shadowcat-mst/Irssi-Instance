package Irssi::Instance::_::Base;

use Mojo::Base qw(-base -signatures);
use Mojo::DynamicMethods qw(-dispatch);

sub BUILD_DYNAMIC ($class, $method, $dyn_methods) {
  return sub ($self, @args) {
    Carp::croak qq{Can't locate object "${method}" via package "${\ref($self)}"}
      unless exists((my $methods = $dyn_methods->{$self})->{$method});
    $self->socket_client->call($methods->{$method}//(), $method, @args);
  }
}

1;
