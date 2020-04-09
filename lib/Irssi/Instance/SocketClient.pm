package Irssi::Instance::SocketClient;

use Import::Into;
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json decode_json);
use Irssi::Instance::Base;
use curry;
use Mojo::Base qw(-base -async_await -signatures);

has 'socket_path';

has 'async';

has 'stream';

has 'buf';

has rq => sub { [] };

has methods_of => sub { {} };

async sub register_methods_for ($self, $obj, $lookup_via) {
  my $pkg = ref($obj);
  my $methods = $self->methods_of->{$pkg} ||= do {
    (my $remote_pkg = $pkg) =~ s/^Irssi::Instance/Irssi/;
    [ await $self->call_p(methods => $remote_pkg) ];
  };
  foreach my $m (@$methods) {
    # Must have been loaded by ::Base or we're screwed already
    Mojo::DynamicMethods::register(
      'Irssi::Instance::Base' => $obj => $m => $lookup_via
    );
    Mojo::DynamicMethods::register(
      'Irssi::Instance::Base' => $obj => "cast_$m" => $lookup_via
    );
  }
  return $obj;
}

sub start { shift->connect(@_) } # should reconnect

sub _connect_p ($self, $path) {
  Mojo::Promise->new->tap(sub ($p) {
    Mojo::IOLoop->client({ path => $path }, sub ($, $err, @result) {
      $err and $p->reject($err) or $p->resolve(@result);
    });
  });
}

async sub connect ($self) {
  my $socket_path = $self->socket_path;
  unless (-S $socket_path) {
    require Irssi::Instance::SocketServer;
    die "Can't connect: ${socket_path} is not a socket.\n\n"
        ."Please check your irssi instance is running and that the socket\n"
        ."server is loaded. The server script can be found at path:\n\n"
        .Irssi::Instance::SocketServer->file_path."\n";
  }
  my $s = await $self->_connect_p($socket_path);
  $s->on(read => $self->curry::weak::_handle_read);
  $self->stream($s)->buf('');
}

my %responses = (done => 'resolve', fail => 'reject');

sub _handle_read ($self, $, $bytes) {
  $self->{buf} .= $bytes;
  while ($self->{buf} =~ s/^(.*?)\n//) {
    my $str = $1;
    my $msg = decode_json($str);
    my ($type, @payload) = @$msg;
    if (my $method = $responses{$type}) {
      die "No request queued" unless my $req = shift @{$self->rq};
      $req->$method(@payload);
    }
  }
  return;
}

sub await ($self, $p) {
  Carp::croak "await method only valid at top level"
    if $p->ioloop->is_running;
  $self->_await($p);
}

sub _await ($self, $p) {
  my (@result, $rejected);
  $p->then(sub { @result = @_ }, sub { $rejected = 1; @result = @_ })->wait;
  if ($rejected) {
    my $reason = $result[0] // 'Promise was rejected';
    die $reason if ref $reason or $reason =~ m/\n\z/;
    Carp::croak $reason;
  }
  return wantarray ? @result : $result[0];

}

sub call ($self, @call) {
  my $p = $self->call_p(@call);
  return $self->async ? $p : $self->await($p);
}

sub cast ($self, @call) {
  $self->stream->write(encode_json(\@call)."\n");
  push @{$self->rq}, Mojo::Promise->new->catch(sub{});
  return $self;
}

async sub call_p ($self, @call) {
  $self->stream->write(encode_json(\@call)."\n");
  push @{$self->rq}, my $p = Mojo::Promise->new;
  return await $self->_expand(await $p);
}

async sub _expand ($self, @payload) {
  my @expanded;
  foreach my $item (@payload) {
    if (ref($item) eq 'HASH') {
      my %exp;
      @exp{keys %$item} = await $self->_expand(values %$item);
      push @expanded, \%exp;
      next;
    }
    if (ref($item) eq 'ARRAY') {
      if (@$item) {
        my $class = $item->[0];
        if (
          defined($class) and !ref($class)
          and $class =~ s/^Irssi::/Irssi::Instance::/
        ) {
          Mojo::Base->import::into($class, 'Irssi::Instance::RemoteObject')
            unless $class->can('new');
          my $obj = $class->new(
            socket_client => $self,
            attrs => await $self->_expand($item->[1]),
          );
          if (my $lookup_via = $item->[2]) {
            await $self->register_methods_for($obj, $lookup_via);
          }
          push @expanded, $obj;
          next;
        }
      }
      push @expanded, [ await $self->_expand(@$item) ];
      next;
    }
    push @expanded, $item;
  }
  return @expanded;
}

1;
