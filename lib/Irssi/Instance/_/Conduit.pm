package Irssi::Instance::_::Conduit;

use Irssi::Instance::_Do;
use Import::Into;
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json decode_json);
use curry;
use Mojo::Util qw(monkey_patch);
use Mojo::Base qw(Mojo::EventEmitter -async_await -signatures);

has 'socket_path';

has 'stream';

has 'buf';

has rq => sub { [] };

our %Did_Setup;

async sub setup_package ($self, $pkg) {
  $Did_Setup{$pkg} ||= do {
    Mojo::Base->import::into($pkg, 'Irssi::Instance::_::Object')
      unless $pkg->can('new');
    (my $remote_pkg = $pkg) =~ s/^Irssi::Instance/Irssi/;
    my @methods = await $self->call(methods => $remote_pkg);
    monkey_patch $pkg => map {
      my $m = $_;
      ($m, sub ($self, @args) {
        $self->conduit->call($self->lookup_via//(), $m => @args)
      });
    } @methods;
    1;
  };
  return $self;
}

sub start { shift->connect(@_) } # should reconnect

async sub connect ($self) {
  my $s = await Mojo::IOLoop->$_do(client => { path => $self->socket_path });
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
          await $self->setup_package($class);
          push @expanded, $class->new(
            conduit => $self,
            attrs => $item->[1],
            ($item->[2] ? (lookup_via => $item->[2]) : ())
          );
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
