package Irssi::Instance::Protocol;

1;

__END__
=head1 NAME

Irssi::Instance::Protocol - The socket protocol for L<Irssi::Instance>

=head1 PROTOCOL

The protocol, in so far as there is one, is newline delimited JSON(Y).

(note: if the first line starts and ends with [] it's assumed to be JSON
as handled by L<JSON::PP> or optionally L<Cpanel::JSON::XS> - if it does
not, it's assumed to be L<JSONY>. Examples will be in L<JSONY> form but
since that's just JSON with less punctuation it should still make sense)

Simple commands:


  >> command "msg -freenode #irssi another test"
  << done

Roughly, a simple command takes the first argument, turns it into a call
to C<Irssi::name_of_command> and invokes it with the rest of the arguments.

Commands are processed and replied to in order received, and if the command
succeeds you will get C<done> followed by the return value. If the C<Irssi::>
call throws an error you will get C<fail> followed by the error thrown.

To call a method on an object, you need instead for the first element of the
command array to be an C<Irssi::> call that looks up the object upon which
you want to call that. So:

  >> [ server_by_tag freenode ] command "msg #irssi test test"
  << done

If a method or function you call returns an object inside the socket server,
this will be converted to

  [ "Irssi::Irc::Server" [ server freenode ] { <attributes> } ]

where the first element is the class inside irssi, the second element is
the thing you need to send back to get at that object again, and the third
element is the hash of attributes, i.e. the stuff documented with ->{} in
the irssi C<perl.txt> document.

To get a list of functions/methods available to call, send:

  >> methods

for the available calls on C<Irssi::> or

  >> methods Irssi::Irc::Server

to get a result of the available calls on an C<Irssi::Irc::Server> object.

To provide a command name, send:

  >> subscribe "command cmdname"

After which you will receive messages of the form:

  << cast "command cmdname" "<command args>" <server> <primary window item>

which you can do whatever you want with. To stop them coming:

  >> unsubscribe "command cmdname"

Similarly, one can subscribe to signals via: subscribe "signal signame".

Note that this only gives you a notification that the signal fired.

For full details on what you can and can't call, please refer to
L<https://github.com/irssi/irssi/blob/master/docs/perl.txt>.

=cut
