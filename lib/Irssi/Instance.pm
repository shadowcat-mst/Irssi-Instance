package Irssi::Instance;

our $VERSION = '0.000001'; # 0.0.1

$VERSION = eval $VERSION;

use Irssi::Instance::SocketClient;
use Mojo::Base qw(Irssi::Instance::Base -signatures -async_await);

has socket_path => sub { "$ENV{HOME}/.irssi.sock" };

has socket_client => sub ($self) {
  Irssi::Instance::SocketClient->new(
    socket_path => $self->socket_path,
    'async' => 0+!!delete $self->{async},
  );
};

sub async ($self, $value = return $self->socket_client->async) {
  $self->socket_client->async($value);
  return $self;
}

sub start ($self) {
  my $p = $self->socket_client
               ->start
               ->then::register_methods_for($self, undef);
  return $p if $self->async;
  return $p->await::this;
}

1;

=head1 NAME

Irssi::Instance - Description goes here

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

 mst - Matt S. Trout (cpan:MSTROUT) <mst@shadowcat.co.uk>

=head1 CONTRIBUTORS

None yet - maybe this software is perfect! (ahahahahahahahahaha)

=head1 COPYRIGHT

Copyright (c) 2020 the Irssi::Instance L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.
