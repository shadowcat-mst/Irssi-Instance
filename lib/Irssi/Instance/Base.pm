package Irssi::Instance::Base;

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
    if ($method =~ s/^cast_//) {
      $sc->cast(@id, $method, @args);
      return $self;
    }
    return $sc->call(@id, $method, @args);
  }
}

sub await ($self, @await) {
  my $sc = $self->socket_client;
  my $p = do {
    if (Scalar::Util::blessed($await[0]) and $await[0]->isa('Mojo::Promise')) {
      @await > 1 ? Mojo::Promise->all(@await) : $await[0];
    } else {
      my ($method, @args) = @await;
      return $self->$method(@args) unless $sc->async;
      $self->$method(@args);
    }
  };
  Carp::croak "await method only valid at top level"
    if $p->ioloop->is_running;
  $sc->_await($p);
}

1;
