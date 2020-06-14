package Irssi::Instance::Base;

use curry;
use Import::Into;
use Async::Methods;
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::Base qw(-base -signatures);
use Mojo::DynamicMethods qw(-dispatch);

has 'socket_client';

sub BUILD_DYNAMIC ($class, $method, $dyn_methods) {
  return sub ($self, @args) {
    Carp::croak qq{Can't locate object "${method}" via package "${\ref($self)}"}
      unless exists((my $methods = $dyn_methods->{$self})->{$method});
    my @id = $methods->{$method}//();
    my $sc = $self->socket_client;
    my $call_method = (
      $method =~ s/^cast_//
        ? 'cast'
        : ($sc->async ? 'call_p' : 'await::call_p')
    );
    return $sc->$call_method(@id, $method, @args);
  }
}

1;
