-module(chat).

%-export([start/0,stop/0,put/2,get/1,remove/1,size/0,create_slaves/1,remove_slaves/1, exit_master/0]).
-export_type([users/0, messages/0, channels/0]).
-export_opaque(key/0).

-type( key() :: non_neg_integer() ).

-record(user, {
	name :: string()
}).

-record(message, {
	user :: user,
	text :: string()
}).

-opaque(users() :: map()).
-opaque(messages() :: map()).

-record(channel, {
	key :: pid(),
	users :: users(),
	messages :: messages()
}).

-opaque(channels() :: map()).


-record(node,{
  key :: pid(),
  pid :: key(),
  channels :: channels()
}).

-record(state,{
  self :: #node{},
  successor :: #node{},
  predecessor = undefined :: undefined | #node{},
  predecessor_monitor :: reference()
}).


-spec start() -> #node{}.
start() ->
  P = spawn(fun() ->
    Self = #node{ key = hash(self()) , pid = self() },
    spawn_link( fun() -> stabilise(Self,Self) end),
    loop(#state{ self = Self, successor = Self })
  end),
  #node{ key = hash(P) , pid = P }.
