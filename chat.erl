-module(chat).

%-export([start/0,stop/0,put/2,get/1,remove/1,size/0,create_slaves/1,remove_slaves/1, exit_master/0]).
-export([start/0,hash/1]). % start/1
-export_type([users/0, messages/0, channels/0]).
-export_opaque([key/0, users/0, messages/0, channels/0]).

%%% CONFIG PARAMETERS %%%%%%%
% number of bits in the keys
-define(KEY_LENGTH,8).
% the format used to print keys
-define(KEY_FORMAT, "~3..0B").
% the delay between different runs of the Stabilise procedure
-define(STABILIZE_INTERVAL,1000).
%%% END OF CONFIG %%%%%%%%%%%

% a shorthand used in the code, do not modfy
-define(KEY_MAX, 1 bsl ?KEY_LENGTH - 1).

% debug macros %%%%%%%%%%%%%%
-ifdef(debug).
-define(DBG(Format,Args),io:format(Format,Args)).
-else.
-define(DBG(Format,Args),true).
-endif.
-define(DBG(Self,Format,Args),?DBG("~s ~s~n",[format_node(Self),io_lib:format(Format,Args)])).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Computes the key for a term.
-spec hash(_) -> key().
hash(T) -> erlang:phash2(T,?KEY_MAX).


-type( key() :: non_neg_integer() ).
-opaque(users() :: map()).
-opaque(messages() :: map()).
-opaque(channels() :: map()).

-record(user, {
	name :: string()
}).

-record(message, {
	user :: user,
	text :: string()
}).

-record(channel, {
	key :: pid(),
	users :: users(),
	messages :: messages()
}).

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
    Self = #node{ key = hash(self()) , pid = self() }
    %spawn_link( fun() -> stabilise(Self,Self) end)
    %loop(#state{ self = Self, successor = Self })
  end),
  #node{ key = hash(P) , pid = P }.

%-spec start(#node{}) -> #node{}.
%start(N) ->
%  
%end.