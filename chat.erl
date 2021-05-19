-module(chat).

%-export([start/0,stop/0,put/2,get/1,remove/1,size/0,create_slaves/1,remove_slaves/1, exit_master/0]).
% -export([start/0,start/2,hash/1,is_key/1,locate_successor/2,format_node/1,format_key/1, master_start/0]).
-export_type([users/0, messages/0]).
-export_opaque([key/0, users/0, messages/0, channels/0]).
-compile(export_all).

%%% CONFIG PARAMETERS %%%%%%%
% number of bits in the keys
-define(KEY_LENGTH,8).
% the format used to print keys
-define(KEY_FORMAT, "~3..0B").
% the delay between different runs of the Stabilise procedure
-define(STABILIZE_INTERVAL,1500).
% the delay between different runs of the Fix_Fingers procedure
%-define(FIX_FINGERS_INTERVAL,1000).
%%% END OF CONFIG %%%%%%%%%%%

-define(TIMEOUT,1000).

% a shorthand used in the code, do not modfy
-define(KEY_MAX, 1 bsl ?KEY_LENGTH - 1).

-type(key() :: non_neg_integer()).
-opaque(users() :: list()).
-opaque(messages() :: list()).

-record(user, {
	name :: string(),
  pid :: pid()
}).

-record(message, {
	user :: user,
	text :: string()
}).

% To user the chat.
%% Chat1Pid ! {join, "user"}
%% 
%% Chat1Pid ! {send, "user", "Hi chat."}
%% --> "Print messages"
%% 
%% Chat1Pid ! {leave, "user"}


% ListChannels
% --> Call ring
% --> Fetch Pids

% A node is a Channel.
-record(node,{
  name = [] :: string(),
  key :: pid(),
  pid :: key(),
  users = [] :: users(),
  messages = [] :: messages()
}).

%% internal state for the main event loop of a chord node.
-record(state,{
  self :: #node{},
  successor :: #node{},
  successors = [] :: list(),
  predecessor = undefined :: undefined | #node{},
  predecessor_monitor :: reference()
}).


%% @doc checks if the argument is a key
-spec is_key(_) -> boolean().
is_key(X) when is_integer(X), 0 =< X, X =< ?KEY_MAX -> true;
is_key(_) -> false.

%% @doc pretty printing untility for keys
-spec format_key(key()) -> string().
format_key(K) -> 
  io_lib:format(?KEY_FORMAT,[K]).

%% @doc Computes the key for a term.
-spec hash(_) -> key().
hash(T) -> erlang:phash2(T,?KEY_MAX).

%% @doc pretty printing untility for chord nodes
-spec format_node(#node{}) -> string().
format_node(N) -> 
  io_lib:format("("++?KEY_FORMAT++" ~p)",[N#node.key,N#node.pid]).

- spec master_start() -> pid().
master_start() ->
  Node = start().
  %_Master = spawn(fun() ->
  %  master(Node)
  %end).


%% @doc Creates a new ring
-spec start() -> #node{}.
start() ->
  P = spawn(fun() ->
    Self = #node{ key = hash(self()) , pid = self(), name = "startNode" },
    spawn_link( fun() -> stabilise(Self,Self,[Self]) end),
    loop(#state{ self = Self, successor = Self })
  end),
  #node{ key = hash(P) , pid = P, name = "startNode" }.

%% @doc Joins an existing ring
-spec start(#node{}, string()) -> #node{}.
start(N, Name) ->
  P = spawn(fun() ->
    Succ = locate_successor(hash(self()), N),
    Self = #node{ key = hash(self()) , pid = self(), name = Name },
    io:format("~p ~n", [Self#node.pid]),
    % NOTE: collisions for hash(self()) are not a problem for the protocol.
    spawn_link( fun() -> stabilise(Self,Succ,[Succ]) end),
    loop(#state{ self = Self, successor = Succ })
  end),
  #node{ key = hash(P) , pid = P, name = Name }.

%% @doc Locate the successor node to Key.
-spec locate_successor(key(),#node{}) -> #node{}.
locate_successor(Key, N) ->
  case is_key(Key) of
    false -> 
      locate_successor(hash(Key), N);
    true -> 
      N#node.pid ! { locate_successor, Key, self() },
      receive
        { successor_of, Key, S } -> S
      end
  end.

%% Event loop of the chord node.
-spec loop(#state{}) -> no_return().
loop(S) ->
  receive
    { locate_successor, Key, ReplyTo} = M ->
      % request to locate the successor of Key--see Locate_Successor(Key)
      case is_handled_by_successor(Key, S) of
        true  -> 
          %io:format("replying ~s to locate request by ~p for ~s. \n",[format_node(S#state.successor),ReplyTo,format_key(Key)]),
          ReplyTo ! {successor_of, Key, S#state.successor };
        _ -> 
          % forward the request to the successor of this node
          %io:format("forwarding locate request by ~p for ~s to ~s. \n",[ReplyTo,format_key(Key),format_node(S#state.successor)]),
          S#state.successor#node.pid ! M
      end,
      loop(S);
    { notify, Pred } ->
      % Implements the Notify procedure of the Chord protocol.
      case S#state.predecessor of
        undefined -> 
          %io:format("Self = ~s, predecessor = ~s. \n",[format_node(S#state.self),format_node(Pred)]),
          loop(S#state{ 
            predecessor = Pred, 
            predecessor_monitor = erlang:monitor(process,Pred#node.pid)
           });
        _ -> 
          case is_in_interval(Pred#node.key, S#state.predecessor#node.key, S#state.self#node.key) of
            true ->
              %io:format("Self = ~s, predecessor = ~s. \n",[format_node(S#state.self), format_node(Pred)]),
              erlang:demonitor(S#state.predecessor_monitor, [flush]),
              loop(S#state{ 
                predecessor = Pred, 
                predecessor_monitor = erlang:monitor(process,Pred#node.pid)
              });
            _ -> 
              loop(S)
          end
      end;
    {'DOWN', Ref, _Type, _Object, _Info} when Ref == S#state.predecessor_monitor ->
      % the predecessor is believed to have failed and removed
      %io:format("predecessor = undefined. \n",[]),
      loop(S#state{ predecessor = undefined, predecessor_monitor = undefined });
    { get_predecessor, ReplyTo } ->
      ReplyTo ! { predecessor_of, S#state.self, S#state.predecessor },
      loop(S);
    { set_successor, Succ } ->
      % io:format("Self = ~s, successor = ~s. \n",[format_node(S#state.self),format_node(Succ)]),
      loop(S#state{successor = Succ});
    { get_successors, ReplyTo, Self } ->
      ReplyTo#node.pid ! { set_successors, S#state.self, S#state.successors, Self },
      loop(S);
    { set_successors, FromNode, Successors, ReplyTo } ->
      NewSuccessors = case length(Successors) >= 8 of
        true -> lists:append([FromNode], lists:droplast(Successors));
        _    -> lists:append([FromNode], Successors)
      end,
      ReplyTo ! { set, NewSuccessors },
      loop(S#state{successors = NewSuccessors});
    { get_name, ReplyTo, Startnode } ->
      %io:format("Startnode id: ~p ~n",[Startnode#node.pid]),
      %io:format("Succ id: ~p ~n",[S#state.successor#node.pid]),
      case Startnode#node.pid == S#state.successor#node.pid of 
        true -> 
          ReplyTo ! {return_name, S#state.self#node.name, S#state.self},
          ReplyTo ! {done},
          loop(S); 
        _ -> 
          ReplyTo ! {return_name, S#state.self#node.name, S#state.self},
          S#state.successor#node.pid ! {get_name, ReplyTo, Startnode},
          loop(S)
      end;
    {user_joined, Username, Pid} ->
      User = #user{name = Username, pid = Pid},
      loop(S#state{self = S#state.self#node{users = lists:append(S#state.self#node.users, [User])}});
    {user_message, User, Message} ->
      Messages = S#state.self#node.messages,
      MessageRecord = #message{user = User, text = Message},
      NewMessages = lists:append(S#state.self#node.messages, [MessageRecord]),
      % Send data to nodes
      lists:foreach(fun(U) ->
        U#user.pid ! {new_message, MessageRecord}
      end, S#state.self#node.users),
      loop(S#state{self = S#state.self#node{messages = NewMessages}});
    { exit } ->
      % io:format("I was exited!"),
      exit(normal);
    { ping, ReplyTo } ->
      ReplyTo ! { pong };
    { remove_node, Node } ->
      % io:format("Deleting ~p ~n", [Node]),
      loop(S#state { successors = lists:dropwhile(fun(MyNode) -> MyNode == Node end, S#state.successors) });
    print_info ->
      % DEBUG
      %io:format("NODE INFO~n  state: ~p~n~n  process info: ~p~n \n",[S, process_info(self())]),
      loop(S)
  end.

%% @doc Implements the Stabilise procedure of the Chord protocol.
-spec stabilise(#node{},#node{}, list()) -> no_return().
stabilise(Self,Successor,Successors) ->
  timer:sleep(?STABILIZE_INTERVAL),
  %io:format("Self: ~s, stabilize with ~s. \n",[format_node(Self), format_node(Successor)]),
  Successor#node.pid ! { get_predecessor, self() },
  NewSuccessor = receive
    { predecessor_of, Successor, undefined } -> Successor;
    { predecessor_of, Successor, X } -> 
      case is_in_interval(X#node.key, Self#node.key, Successor#node.key) of
        true ->
          Self#node.pid ! { set_successor, X },
          X;
        _ ->
          Successor
      end
  after ?TIMEOUT ->
    % io:format("~p: is down.~n",[Successor#node.pid]),
    
    lists:foreach(fun(N) ->
      N#node.pid ! { remove_node, Successor}
    end, Successors),
    Self#node.pid ! { remove_node, Successor},

    case length(Successors) > 1 of
      true -> 
        NextSuccessor = lists:nth(2, Successors),
        MyNewSuccessors = lists:delete(Successor, Successors);
      _ ->
        NextSuccessor = Self,
        MyNewSuccessors = [Self]
    end,
    stabilise(Self,NextSuccessor,MyNewSuccessors)
  end,
  NewSuccessor#node.pid ! { notify, Self },
  NewSuccessor#node.pid ! { get_successors, Self, self() },
  NewSuccessors = receive
    { set, Data} -> Data
  end,
  % io:format("Self: ~s, notify ~s. list ~p ~n",[format_node(Self), format_node(NewSuccessor), NewSuccessors]),
  stabilise(Self,NewSuccessor,NewSuccessors).

%% @doc checks if Key is handled by the successor of the current node
-spec is_handled_by_successor(key(),#state{}) -> boolean().
is_handled_by_successor(Key, S) -> 
  is_in_right_closed_interval(Key,S#state.self#node.key,S#state.successor#node.key).

%% @doc checks if X lies in the key interval (Y,Z].
-spec is_in_right_closed_interval(key(),key(),key()) -> boolean().
is_in_right_closed_interval(X, Y, Z) when Y < Z ->
  (Y < X) and (X =< Z);
is_in_right_closed_interval(X, Y, Z) ->
  (X =< Z) or (Y < X).

%% @doc checks wether X lies in the interval (Y,Z).
-spec is_in_interval(key(),key(),key()) -> boolean().
is_in_interval(X,Y,Z) when Y < Z ->
  (Y < X) and (X < Z);
is_in_interval(X,Y,Z) ->
  (X < Z) or (Y < X).