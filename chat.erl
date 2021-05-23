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
-define(STABILIZE_INTERVAL,100).
% the delay between different runs of the Fix_Fingers procedure
%-define(FIX_FINGERS_INTERVAL,1000).
%%% END OF CONFIG %%%%%%%%%%%

-define(TIMEOUT,750).

% a shorthand used in the code, do not modfy
-define(KEY_MAX, 1 bsl ?KEY_LENGTH - 1).

-type(key() :: non_neg_integer()).
-opaque(users() :: list()).
-opaque(messages() :: list()).
-opaque(q_entries() :: list()).

% Record for the users
-record(user, {
	name :: string(),
  pid :: pid()
}).

% Record for the messages
-record(message, {
	user :: user,
	text :: string()
}).

% Record used in the algorithm for total ordering
-record(q_entry,{
  m :: #message{},
  tag :: integer(),
  timestamp :: integer(),
  deliverable :: atom()
}).

% A node is a group.
-record(node,{
  name = [] :: string(),
  key :: pid(),
  pid :: key(),
  users = [] :: users(),
  messages = [] :: q_entries(),
  temp_q = [] :: q_entries(),
  deliv_q = [] :: q_entries()
}).

%% internal state for the main event loop of a chord node.
-record(state,{
  self :: #node{},
  successor :: #node{},
  successors = [] :: list(),
  predecessor = undefined :: undefined | #node{},
  predecessor_monitor :: reference(),
  clock = 0 :: integer()
}).

% All Messages:
%   { locate_successor, key(), pid() }
%   { notify, node{} }
%   { 'DOWN', reference(), _Type, _Object, _Info } - Ved ikke lige hvad jeg skal skrive af typer her
%   { get_predecessor, pid() }
%   { set_successor, node{} }
%   { get_successors, pid(), pid() }
%   { set_successors, pid(), list(), pid() }
%   { get_name, pid(), node{} }
%   { return_name, string(), node{} }
%   { done }
%   { user_joined, string(), pid() }
%   { group_users, pid() }
%   { return_group_users, users() }
%   { revise_loop, message{}, pid(), integer(), integer() }
%   { exit }
%   { remove_node, node{} }
%   { final_messages, q_entries() }
%   { find_user, string(), pid(), node{} }
%   { return_users, tuple() }
%   print_info
%   { proposed_ts, pid(), integer(), integer() }
%   { predecessor_of, node{}, node{} }


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

% Returns the node which is the masternode
- spec master_start() -> pid().
master_start() ->
  Node = start().

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

%% @doc Implements the Stabilise procedure of the Chord protocol.
-spec stabilise(#node{},#node{}, list()) -> no_return().
stabilise(Self,Successor,Successors) ->
  timer:sleep(?STABILIZE_INTERVAL),
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
    Self#node.pid ! { set_successor, NextSuccessor },
    stabilise(Self,NextSuccessor,MyNewSuccessors)
  end,
  NewSuccessor#node.pid ! { notify, Self },
  NewSuccessor#node.pid ! { get_successors, Self, self() },
  NewSuccessors = receive
    { set, Data} -> Data
  end,
  Self#node.pid ! { set_successor, NewSuccessor },
  stabilise(Self,NewSuccessor,NewSuccessors).

%% Event loop of the chord node.
-spec loop(#state{}) -> no_return().
loop(S) ->
  receive
    { locate_successor, Key, ReplyTo} = M ->
      % request to locate the successor of Key--see Locate_Successor(Key)
      case is_handled_by_successor(Key, S) of
        true  -> ReplyTo ! {successor_of, Key, S#state.successor };
        _ -> 
          % forward the request to the successor of this node
          S#state.successor#node.pid ! M
      end,
      loop(S);
    { notify, Pred } ->
      % Implements the Notify procedure of the Chord protocol.
      case S#state.predecessor of
        undefined -> 
          loop(S#state{ 
            predecessor = Pred, 
            predecessor_monitor = erlang:monitor(process,Pred#node.pid)
           });
        _ -> 
          case is_in_interval(Pred#node.key, S#state.predecessor#node.key, S#state.self#node.key) of
            true ->
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
      loop(S#state{ predecessor = undefined, predecessor_monitor = undefined });
    { get_predecessor, ReplyTo } ->
      ReplyTo ! { predecessor_of, S#state.self, S#state.predecessor },
      loop(S);
    { set_successor, Succ } ->
      loop(S#state{successor = Succ});
    { get_successors, ReplyTo, Self } ->
      % Gets the node's list of successors
      ReplyTo#node.pid ! { set_successors, S#state.self, S#state.successors, Self },
      loop(S);
    { set_successors, FromNode, Successors, ReplyTo } ->
      % Sets the node's list of successors
      NewSuccessors = case length(Successors) >= 8 of
        true -> lists:append([FromNode], lists:droplast(Successors));
        _    -> lists:append([FromNode], Successors)
      end,
      ReplyTo ! { set, NewSuccessors },
      loop(S#state{successors = NewSuccessors});
    { get_name, ReplyTo, Startnode } ->
      % Gets the name of the groupchat (the node) and thens the request to its successor
      case Startnode#node.pid == S#state.successor#node.pid of  % unless it as reached where it started in the ring 
        true -> 
          ReplyTo ! {return_name, S#state.self#node.name, S#state.self},
          timer:sleep(?TIMEOUT),
          ReplyTo ! {done},
          loop(S); 
        _ -> 
          ReplyTo ! {return_name, S#state.self#node.name, S#state.self},
          S#state.successor#node.pid ! {get_name, ReplyTo, Startnode},
          loop(S)
      end;
    { user_joined, Username, Pid } ->
      % A users as joined the groupchat
      User = #user{name = Username, pid = Pid},
      loop(S#state{self = S#state.self#node{users = lists:append(S#state.self#node.users, [User])}});
    { group_users, ReplyTo } ->
      % Request for the groupchat's (the node's) list of users
      ReplyTo ! {return_group_users, S#state.self#node.users},
      loop(S); 
    { revise_loop, Message, ReplyTo, Tag, Clock } ->
      % Message used in the algorithm for total ordering, finds the max of all the possible timestamps from the users
      lists:foreach(fun(U) ->
        U#user.pid ! {revise_ts, Message, ReplyTo, Tag, Clock}
      end, S#state.self#node.users),
      TimestampList = get_timestamp([], S#state.self#node.users),
      Max = case length(TimestampList) of 
        0 -> 0;
        1 -> lists:nth(1, TimestampList);
        _ -> lists:max(get_timestamp([], S#state.self#node.users))
      end,
      lists:foreach(fun(U) ->
        U#user.pid ! {final_ts, ReplyTo, Tag, Max}
      end, S#state.self#node.users),
      loop(S);
    { exit } -> exit(normal);
    { remove_node, Node } ->
      % When a node is belived to be down, it is then removed from the node's successor lists
      loop(S#state { successors = lists:dropwhile(fun(MyNode) -> MyNode == Node end, S#state.successors) });
    { final_messages, Deliv_q } ->
      % From the algorithm for total ordering, sorted list of messages based on timestamp
      loop(S#state{self = S#state.self#node{messages = lists:umerge(S#state.self#node.messages, Deliv_q)} });        
    { find_user, Name, ReplyTo, Startnode } ->
      % Gets the user which has Name as its name
      case Startnode#node.pid == S#state.successor#node.pid of
        true ->
          ReplyTo ! {return_users, find_user(S#state.self, Name)},
          ReplyTo ! {done},
          loop(S);
        _ ->
          ReplyTo ! {return_users, find_user(S#state.self, Name)},
          S#state.successor#node.pid ! {find_user, Name, ReplyTo, Startnode},
          loop(S)
      end;
    print_info ->
      % DEBUG
      io:format("NODE INFO~n  state: ~p~n~n  process info: ~p~n \n",[S, process_info(self())]),
      loop(S)
  end.

% Finds the user with the name Name in the node's list of users
find_user(Node, Name) ->
  Users = Node#node.users,
  case length([X || X <- Users, string:equal(X#user.name, Name)]) > 0 of
    true -> {Node#node.name, Name};
    _ -> undefined
  end.

% Waits on the message proposed_ts from all the users, returns after some timeout
get_timestamp(List, Users) ->
  receive
    { proposed_ts, _ReplyTo, _Tag, Timestamp } ->
      case length(List) >= length(Users) of 
        true -> List;
        _ -> get_timestamp(lists:append(List, [Timestamp]), Users)
      end
  after ?TIMEOUT ->
    List
  end.

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