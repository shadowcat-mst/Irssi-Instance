package Irssi::Instance::SocketClient;

use Irssi::Instance::_Do;
use Import::Into;
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json decode_json);
use Irssi::Instance::_::Base;
use curry;
use Mojo::Base qw(-base -async_await -signatures);

has 'socket_path';

has 'stream';

has 'buf';

has rq => sub { [] };

has methods_of => sub { {} };

async sub register_methods_for ($self, $obj, $lookup_via) {
  my $pkg = ref($obj);
  my $methods = $self->methods_of->{$pkg} ||= do {
    (my $remote_pkg = $pkg) =~ s/^Irssi::Instance/Irssi/;
    [ await $self->call(methods => $remote_pkg) ];
  };
  foreach my $m (@$methods) {
    # Must have been loaded by ::Base or we're screwed already
    Mojo::DynamicMethods::register(
      'Irssi::Instance::_::Base' => $obj => $m => $lookup_via
    );
  }
  return $obj;
}

sub start { shift->connect(@_) } # should reconnect

async sub connect ($self) {
  my $socket_path = $self->socket_path;
  unless (-S $socket_path) {
    require Irssi::Instance::SocketServer;
    die "Can't connect: ${socket_path} is not a socket.\n\n"
        ."Please check your irssi instance is running and that the socket\n"
        ."server is loaded. The server script can be found at path:\n\n"
        .Irssi::Instance::SocketServer->file_path."\n";
  }
  my $s = await Mojo::IOLoop->$_do(client => { path => $socket_path });
  $s->on(read => $self->curry::weak::_handle_read);
  $self->stream($s)->buf('');
}

sub _handle_read ($self, $, $bytes) {
  $self->{buf} .= $bytes;
  while ($self->{buf} =~ s/^(.*?)\n//) {
    my $str = $1;
    my $msg = decode_json($str);
    my ($type, @payload) = @$msg;
    if ($type eq 'done' or $type eq 'fail') {
      die "No request queued" unless my $req = shift @{$self->rq};
      $req->$type(@payload);
    }
  }
  return;
}

async sub call ($self, @call) {
  $self->stream->write(encode_json(\@call)."\n");
  push @{$self->rq}, my $f = Future::Mojo->new;
  return await $self->_expand(await $f);
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
          Mojo::Base->import::into($class, 'Irssi::Instance::_::RemoteObject')
            unless $class->can('new');
          my $obj = $class->new(socket_client => $self, attrs => $item->[1]);
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
