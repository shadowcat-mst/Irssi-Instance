use strict;
use warnings;
use IO::Socket::UNIX;

{
  no warnings 'redefine';
  sub IrssiSockDestructionGuard::DESTROY { $_[0]->() }
}

sub guard (&) {
  bless($_[0], 'IrssiSockDestructionGuard');
}

our $J_CLASS;
BEGIN {
  if (eval { require Cpanel::JSON::XS; 1 }) {
    $J_CLASS = 'Cpanel::JSON::XS';
  } else {
    require JSON::PP;
    $J_CLASS = 'JSON::PP';
  }
}

use Irssi;
use utf8;
use Scalar::Util qw(blessed);

our $JSON = $J_CLASS->new->allow_nonref(1)->canonical(1)->convert_blessed(1);

sub debug { Irssi::print($_[0]) }

my $sock = "$ENV{HOME}/.irssi.sock";

unlink($sock) if -e $sock;

my $server = IO::Socket::UNIX->new(
  Type => SOCK_STREAM,
  Local => $sock,
  Listen => 1
) or die $!;

$server->blocking(0);

my $server_tag = Irssi::input_add($server->fileno, INPUT_READ, sub {
  return unless my $client = $server->accept;
  $client->blocking(0);
  ${*$client}{tag}
    = Irssi::input_add(
        $client->fileno, INPUT_READ, \&handle_client_read, $client
      );
  ${*$client}{buf} = '';
  ${*$client}{id} = my $id = ("$client" =~ /(0x[0-9a-f]+)/)[0];
  ${*$client}{cleanup} = guard {
    debug "Client ${id} disconnected";
  };
  debug "Client ${id} connected";
}, undef);

my %lookups = (
  'Irssi::Irc::Server' => sub { [ server => $_[0]->{tag} ] },
  'Irssi::Irc::Channel' => sub {
    [ [ server => $_[0]->{server}{tag} ] => channel => $_[0]->{name} ]
  },
  'Irssi::UI::Window' => sub { [ window => $_[0]->{refnum} ] },
);

sub deflate_blessed {
  my ($obj) = @_;
  if (my ($type) = ref($obj) =~ /^(Irssi::.+)$/ and eval { 1+keys %$obj }) {
    [ $type => {
      map {
        my $val = $obj->{$_};
        (defined($val) && length($val) ? ($_ => $val) : ());
      } sort keys %$obj
    }, ($lookups{$type}||sub { () })->($obj) ];
  } else {
    "${obj}"
  }
}

sub client_send {
  my ($client, $raw) = @_;
  my $cooked = do {
    if ((${*$client}{protocol}||'') eq 'JSONY') {
      join ' ', map encode_jsony($_), @$raw;
    } else {
      local *UNIVERSAL::TO_JSON = \&deflate_blessed;
      $JSON->encode($raw);
    }
  };
  $client->say($cooked);
}

sub encode_jsony {
  my ($value) = @_;
  $value = deflate_blessed $value if blessed $value;
  my $ref = ref($value);
  if (!$ref and defined($value)) {
    return $value if $value =~ /^[A-Za-z_][A-Za-z0-9_]+$/;
    no warnings 'numeric';
    return $value
      if !utf8::is_utf8($value)
      && length((my $dummy = '') & $value)
      && 0 + $value eq $value
      && $value * 0 == 0;
  }
  if ($ref eq 'ARRAY') {
    return join ' ', '[', (map encode_jsony($_), @$value), ']';
  }
  if ($ref eq 'HASH') {
    my @values = map +($_ => $value->{$_}), sort keys %$value;
    return join ' ', '{', (map encode_jsony($_), @values), '}';
  }
  return $JSON->encode($value);
}

sub client_close {
  my ($client, $last) = @_;
  client_send $client, $last if $last;
  Irssi::input_remove(${*$client}{tag});
  return 1;
}

sub handle_client_read {
  my ($client) = @_;
  if ($client->sysread(${*$client}{buf}, 131072, 0)) {
    while (${*$client}{buf} =~ s/^(.*?)\n//) {
      my $line = $1;
      handle_client_line($client, $line);
    }
  } else {
    client_close $client;
  }
}

our $JSONY_ERR;

sub handle_client_line {
  my ($client, $line) = @_;
  debug "Client ${\${*$client}{id}} sent ${line}";
  client_close $client and return unless length $line;
  my $decoder = ${*$client}{decoder} ||= do {
    if ($line =~ /^\[/ and $line =~ /\]$/) {
      ${*$client}{protocol} = 'JSON';
      sub { $JSON->decode($_[0]) }
    } else {
      ${*$client}{protocol} = 'JSONY';
      unless ($INC{'JSONY.pm'} or $JSONY_ERR) {
        eval { require JSONY; 1 } or do {
          ($JSONY_ERR = $@) =~ s/\n\z//;
        };
      }
      if ($JSONY_ERR) {
        client_close $client => [
          FATAL
            => "Unable to enter JSONY mode, JSONY.pm failed to load"
            => $JSONY_ERR
        ];
        return;
      }
      sub {
        my $ret = JSONY->load($_[0]);
        shift @$ret if $ret->[0] eq '!';
        $ret;
      };
    }
  };
  my $payload = eval { $decoder->($line) } or do {
    client_close $client => [
      FATAL
        => "Failure parsing line", $@
    ];
    return;
  };
  debug "Got object: ".$JSON->encode($payload);
  handle_client_request($client, $payload);
}

sub handle_client_request {
  my ($client, $request) = @_;
  return client_close $client => [ FATAL => "No command provided" ]
    unless my ($call, @args) = @$request;
  return if $call eq '#';
  if (${*$client}{in_call}) {
    push @{${*$client}{queued}}, $request;
    return;
  }
  eval {
    if (my $ret = handle_call($client, 'Irssi', $call, @args)) {
      client_send $client => $ret;
    }
    1;
  } or client_send $client => [ fail => DIED => $@ ];
}

my %special = (
  methods => sub {
    my ($client, $inv, $arg) = @_;
    my $pkg = ref($inv) || $arg || $inv;
    return [ done => subs_of_package($pkg) ];
  },
  Irssi => {
    server => sub {
      my ($client, $inv, $arg) = @_;
      my @by_name;
      my $server = do {
        if (my $tag = (ref($arg) ? $arg->{tag} : $arg)) {
          @by_name = (tag => $tag);
          Irssi::server_find_tag($tag);
        } elsif (my $net = $arg->{chatnet}) {
          @by_name = (net => $net);
          Irssi::server_find_chatnet($net);
        } else {
          return [ fail => "No tag or net supplied" ];
        }
      };
      return [ fail => "No such server" => @by_name ] unless $server;
      return [ done => $server ];
    },
    window => sub {
      my ($client, $inv, $arg) = @_;
      return [ fail => "No such window" => $arg ]
        unless my $window = Irssi::window_find_refnum($arg);
      return [ done => $window ];
    },
  },
  'Irssi::Irc::Server' => {
    list => \&server_call_list,
    msg => \&inv_call_msg,
    cmd => \&inv_call_cmd,
    channel => sub {
      my ($client, $inv, $arg) = @_;
      my $ch = $inv->channel_find($arg);
      return [ fail => "No such channel" => $inv->{tag}, $arg ] unless $ch;
      return [ done => $ch ];
    },
    channel_names => sub {
      my ($client, $inv) = @_;
      # This is wrong in the presence of channel keys and needs fixing if so
      [ done => split ',', $inv->get_channels ];
    },
    channels => sub {
      my ($client, $inv) = @_;
      [ done => map $inv->channel_find($_), split ',', $inv->get_channels ]
    },
  },
);

sub subs_of_package {
  my ($package) = @_;
  no strict 'refs';
  my @inpkg = grep !/::\z/ && /^[a-z]/ && exists &{"${package}::${_}"},
    keys %{"${package}::"};
  return sort @inpkg, keys %{$special{$package}||{}};
}

sub handle_call {
  my ($client, $inv, $call, @args) = @_;
  if (ref($call) eq 'ARRAY') {
    my ($ok, $thing, @rest) = @{handle_call($client, $inv, @$call)};
    if ($ok eq 'fail') {
      client_send $client => [ $ok, $thing, @rest ];
      return;
    }
    $inv = $thing;
    $call = shift @args;
  }
  unshift @args, $inv;
  my $pkg = (my $class = blessed($inv)) || $inv;
  my $handler = (
    $call =~ /^\.(.*)$/
      ? do { my $key = $1; sub { [ done => $inv->{$key} ] } }
      : ($special{$call} || $special{$pkg}{$call})
  );
  if (!$handler and my $sub = $inv->can($call)) {
    shift @args unless $class;
    $handler = sub { shift; [ done => $sub->(@_) ] };
  }
  unless ($handler) {
    client_close $client => [ FATAL => "No such method on ${pkg}" => $call ];
    return;
  }
  $handler->($client, @args);
}

sub inv_call_cmd {
  my ($client, $inv, @args) = @_;
  $inv->send_raw(join ' ', @args);
  return [ 'done' ];
}

sub inv_call_msg {
  my ($client, $inv, $name, @args) = @_;
  my $msg = pop @args;
  if ($name eq 'action') {
    $msg = "\x01ACTION ${msg}\x01";
    $name = 'privmsg';
  }
  $msg = ":${msg}" if length $msg;
  inv_call_cmd $client, $inv, $name, @args, $msg;
}

sub server_call_list {
  my ($client, $inv) = @_;
  ${*$client}{in_call} = 1;
  my $id = ${*$client}{id};
  my @parts = qw(liststart list listend);
  my %names = (
    map +($_ => "redir control_port_${id}_$_"), @parts
  );
  my @names;
  my $on_done;
  my %code = (
    liststart => sub {},
    list => sub {
      my ($server, $data) = @_;
      push @names, (split ' ', $data)[1];
    },
    listend => sub {
      $on_done->();
    }
  );
  Irssi::signal_add({ map +($names{$_} => $code{$_}), @parts });
  $inv->redirect_event("list", 1, '', 0, undef, {
    "event 321" => $names{liststart},
    "event 322" => $names{list},
    "event 323" => $names{listend},
  });
  $on_done = sub {
    Irssi::signal_remove($names{$_} => $code{$_}) for @parts;
    client_send $client => [ done => @names ];
    ${*$client}{in_call} = 0;
    while (!${*$client}{in_call} and @{${*$client}{queued}||[]}) {
      handle_client_request($client, shift @{${*$client}{queued}});
    }
  };
  $inv->send_raw("list");
  return;
}







