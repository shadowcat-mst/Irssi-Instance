package Irssi::Instance::_Do;

use Mojo::Promise;
use Future::Mojo;
use Exporter 'import';
use Mojo::Base qw(-strict -signatures);

our @EXPORT = qw($_do $_f $_get);

our $_do = sub ($self, $method, @args) {
  Mojo::Promise->new->tap(sub ($p) {
    $self->$method(@args, sub {
      my (undef, $err, @result) = @_;
      $err and $p->reject($err) or $p->resolve(@result);
      return;
    });
  });
};

our $_f = sub ($p) {
  return $p if $p->isa('Future');
  $p->with_roles('+Futurify')->futurify;
};

our $_get = sub ($p) { $p->$_f->get };

1;
