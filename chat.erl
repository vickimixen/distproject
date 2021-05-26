-module(chat).
-export([start/2,start/0,hash/1]).
-export_type([users/0, messages/0]).
-export_opaque([key/0, users/0, messages/0, channels/0]).

%%% CONFIG PARAMETERS %%%%%%%
% number of bits in the keys
-define(KEY_LENGTH,8).
% the format used to print keys
-define(KEY_FORMAT, "~3..0B").
% the delay between different runs of the Stabilise procedure
-define(STABILIZE_INTERVAL,100).
%%% END OF CONFIG %%%%%%%%%%%

-define(TIMEOUT,750).

% a shorthand used in the code, do not modify
-define(KEY_MAX, 1 bsl ?KEY_LENGTH - 1).

-type(key() :: non_neg_integer()).
% This opaque is simply used to hide the fact that our users are simply a list. We make sure to only append records of the user type to the list to use it as a list of User.
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
	user :: #user{},
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
%   { notify, #node{} }
%   { 'DOWN', reference(), atom(), pid(), atom() } 
%   { get_predecessor, pid() }
%   { set_successor, #node{} }
%   { get_successors, pid(), pid() }
%   { set_successors, pid(), list(), pid() }
%   { get_name, pid(), #node{} }
%   { return_name, string(), #node{} }
%   { done }
%   { user_joined, string(), pid() }
%   { group_users, pid() }
%   { return_group_users, users() }
%   { revise_loop, #message{}, pid(), integer(), integer() }
%   { exit }
%   { remove_node, #node{} }
%   { final_messages, q_entries() }
%   { find_user, string(), pid(), node{} }
%   { return_users, tuple() }
%   print_info
%   { proposed_ts, pid(), integer(), integer() }
%   { predecessor_of, #node{}, #node{} }


%% @doc checks if the argument is a key.
%% @param X value to check if is key.
-spec is_key(_) -> boolean().
is_key(X) when is_integer(X), 0 =< X, X =< ?KEY_MAX -> true;
is_key(_) -> false.

%% @doc pretty printing utility for keys
%% @param K is a key.
-spec format_key(key()) -> string().
format_key(K) -> 
  io_lib:format(?KEY_FORMAT,[K]).

%% @doc Computes the key for a term.
%% @param T value to be hashed.
-spec hash(_) -> key().
hash(T) -> erlang:phash2(T,?KEY_MAX).

%% @doc pretty printing utility for chord nodes.
%% @param N is the node to be formatted.
-spec format_node(#node{}) -> string().
format_node(N) -> 
  io_lib:format("("++?KEY_FORMAT++" ~p)",[N#node.key,N#node.pid]).

%% @doc Returns the node which is the masternode.
%-spec master_start() -> #node{}.
%master_start() ->
%  Node = start().

%% @doc Creates a new ring.
-spec start() -> #node{}.
start() ->
  P = spawn(fun() ->
    Self = #node{ key = hash(self()) , pid = self(), name = "startNode" },
    spawn_link( fun() -> stabilise(Self,Self,[Self]) end),
    loop(#state{ self = Self, successor = Self })
  end),
  %#node{ key = hash(P) , pid = P, name = "startNode" }.
  {node(),pid_to_list(P)}.

%% @doc Joins an existing ring.
%% @param N is a node in a existing ring.
%% @param Name is the name of the group node joining the ring.
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
%% @param Key is the key of the node to get a successor.
%% @param N is a node in the ring.
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
%% @param Self is the node to be stabilised.
%% @param Successor is the node currently believed to be successor.
%% @param Successors is the nodes list of successors.
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

%% @doc Event loop of the chord node.
%% @param S is the state of the node.
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
    { get_name, ReplyTo, StartPid } ->
      % Gets the name of the groupchat (the node) and then sends the request to its successor
      case StartPid == S#state.successor#node.pid of  % unless it as reached where it started in the ring 
        true -> 
          ReplyTo ! {return_name, S#state.self#node.name, S#state.self},
          timer:sleep(?TIMEOUT),
          ReplyTo ! {done},
          loop(S); 
        _ -> 
          ReplyTo ! {return_name, S#state.self#node.name, S#state.self},
          S#state.successor#node.pid ! {get_name, ReplyTo, StartPid},
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
        _ -> lists:max(TimestampList)
      end,
      lists:foreach(fun(U) ->
        U#user.pid ! {final_ts, ReplyTo, Tag, Max}
      end, S#state.self#node.users),
      loop(S);
    { exit } -> exit(normal);
    { remove_node, Node } ->
      % When a node is believed to be down, it is then removed from the node's successor lists
      loop(S#state { successors = lists:dropwhile(fun(MyNode) -> MyNode == Node end, S#state.successors) });
    { final_messages, Deliv_q } ->
      % From the algorithm for total ordering, sorted list of messages based on timestamp
      SortedLargeMess = lists:sort(fun(X, Y) -> X#q_entry.timestamp > Y#q_entry.timestamp end, lists:umerge(S#state.self#node.messages, Deliv_q)),
      NewMessages = lists:sublist(SortedLargeMess, 1, 10),
      Sortedsmall = lists:sort(fun(X, Y) -> X#q_entry.timestamp < Y#q_entry.timestamp end, NewMessages),
      loop(S#state{self = S#state.self#node{messages = Sortedsmall} });        
    { find_user, Name, ReplyTo, StartPid } ->
      % Gets the user which has Name as its name
      case StartPid == S#state.successor#node.pid of
        true ->
          ReplyTo ! {return_users, find_user(S#state.self, Name)},
          ReplyTo ! {done},
          loop(S);
        _ ->
          ReplyTo ! {return_users, find_user(S#state.self, Name)},
          S#state.successor#node.pid ! {find_user, Name, ReplyTo, StartPid},
          loop(S)
      end;
    print_info ->
      % DEBUG
      io:format("NODE INFO~n  state: ~p~n~n  process info: ~p~n \n",[S, process_info(self())]),
      loop(S)
  end.

%% @doc Finds the user with the a given name in the node's list of users.
%% @param Node is the node to get users from.
%% @param Name is the name of the user to find.
-spec find_user(#node{}, string()) -> tuple().
find_user(Node, Name) ->
  Users = Node#node.users,
  case length([X || X <- Users, string:equal(X#user.name, Name)]) > 0 of
    true -> {Node#node.name, Name};
    _ -> undefined
  end.

%% @doc Waits on the message proposed_ts from all the users, returns after some timeout.
%% @param List is the list to add timestamps to.
%% @param Users is the list of users the message have been sent to.
-spec get_timestamp(list(),list()) -> list().
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

%% @doc checks if Key is handled by the successor of the current node.
%% @param Key is the key to check.
%% @param S is a state containing the node key and successor key.
-spec is_handled_by_successor(key(),#state{}) -> boolean().
is_handled_by_successor(Key, S) -> 
  is_in_right_closed_interval(Key,S#state.self#node.key,S#state.successor#node.key).

%% @doc checks if X lies in the key interval (Y,Z].
%% @param X value to check.
%% @param Y where the interval starts.
%% @param Z where the interval ends.
-spec is_in_right_closed_interval(key(),key(),key()) -> boolean().
is_in_right_closed_interval(X, Y, Z) when Y < Z ->
  (Y < X) and (X =< Z);
is_in_right_closed_interval(X, Y, Z) ->
  (X =< Z) or (Y < X).

%% @doc checks whether X lies in the interval (Y,Z).
%% @param X value to check.
%% @param Y where the interval starts.
%% @param Z where the interval ends.
-spec is_in_interval(key(),key(),key()) -> boolean().
is_in_interval(X,Y,Z) when Y < Z ->
  (Y < X) and (X < Z);
is_in_interval(X,Y,Z) ->
  (X < Z) or (Y < X).