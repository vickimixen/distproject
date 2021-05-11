-module(chat).

-record(user, {
	name :: string()
}).

-record(message, {
	user :: user(),
	text :: string()
}).

-opaque(users() :: map()).
-opaque(messages() :: map()).

-record(channel, {
	key :: pid(),
  	users :: users(),
  	messages :: messages()
}).



-record(node,{
  key :: pid(),
  pid :: key()
}).

-record(state,{
  self :: #node{},
  successor :: #node{},
  predecessor = undefined :: undefined | #node{},
  predecessor_monitor :: reference()
}).
