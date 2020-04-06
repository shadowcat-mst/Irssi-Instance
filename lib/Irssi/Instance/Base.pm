package Irssi::Instance::Base;

use Mojo::Promise;
use Mojo::Base qw(-base -signatures);
use Mojo::DynamicMethods qw(-dispatch);

sub BUILD_DYNAMIC ($class, $method, $dyn_methods) {
  return sub ($self, @args) {
    Carp::croak qq{Can't locate object "${method}" via package "${\ref($self)}"}
      unless exists((my $methods = $dyn_methods->{$self})->{$method});
    $self->socket_client->call($methods->{$method}//(), $method, @args);
  }
}

sub await ($inv, @await) {
  my $p = do {
    if (Scalar::Util::blessed($await[0]) and $await[0]->isa('Mojo::Promise')) {
      @await > 1 ? Mojo::Promise->all(@await) : $await[0];
    } else {
      my ($method, @args) = @await;
      $inv->$method(@args);
    }
  };
  Carp::croak "await method only valid at top level"
    if $p->ioloop->is_running;
  my (@result, $rejected);
  $p->then(sub { @result = @_ }, sub { $rejected = 1; @result = @_ })->wait;
  if ($rejected) {
    my $reason = $result[0] // 'Promise was rejected';
    die $reason if ref $reason or $reason =~ m/\n\z/;
    Carp::croak $reason;
  }
  return wantarray ? @result : $result[0];
}

1;
