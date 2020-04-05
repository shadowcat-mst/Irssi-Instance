package Irssi::Instance::_::Conduit;

use Irssi::Instance::_Do;
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json decode_json);
use curry;
use Class::Method::Modifiers;
use Mojo::Util qw(monkey_patch);
use Mojo::Base qw(Mojo::EventEmitter -async_await -signatures);

has 'socket_path';

has 'stream';

has 'buf';

has rq => sub { [] };

around new => sub ($orig, $class, @args) {
  $class->$orig(@args)
        ->buf('')
        ->tap(sub ($self) {
            $self->on(msg => $self->curry::weak::_handle_msg)
          });
};

our %Methods_Of;

async sub _ensure_methods ($self, $pkg) {
  $Methods_Of{$pkg} ||= do {
    my @methods = await $self->call(methods => $pkg);
    (my $inst_pkg = $pkg) =~ s/^Irssi/Irssi::Instance/;
    monkey_patch $inst_pkg => map {
      my $m = $_;
      ($m, sub { shift->conduit->call($m => @_) })
    } @methods;
    \@methods
  };
}

sub start { shift->connect(@_) } # should reconnect

async sub connect ($self) {
  my $s = await Mojo::IOLoop->$_do(client => { path => $self->socket_path });
  $self->stream($s);
  $s->on(read => $self->curry::weak::_handle_read);
  await $self->_ensure_methods('Irssi');
  $self;
}

sub _handle_read ($self, $, $bytes) {
  $self->{buf} .= $bytes;
  while ($self->{buf} =~ s/^(.*?)\n//) {
    my $str = $1;
    my $msg = decode_json($str);
    $self->emit(msg => $msg);
  }
  return;
}

sub _handle_msg ($self, $, $msg) {
  my ($type, @payload) = @$msg;
  if ($type eq 'done' or $type eq 'fail') {
    die "No request queued" unless my $req = shift @{$self->rq};
    $req->$type(@payload);
  }
}

async sub call ($self, @call) {
  $self->stream->write(encode_json(\@call)."\n");
  push @{$self->rq}, my $f = Future::Mojo->new;
  await $f;
}

1;
