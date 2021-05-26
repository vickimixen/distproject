-module(ui).
-export([start/0, join/1]).
-import_all(chat).

-define(PRINT_INTERVAL,1500).
-define(SLEEP_MIN,2000).

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
  messages = [] :: messages(),
  temp_q = [] :: q_entries(),
  deliv_q = [] :: q_entries()
}).

% All Messages
%   { return_name, string(), #node{} }
%   { done }
%   { return_group_users, users() }
%   { find_user, string(), pid(), #node{} }
%   { return_users, tuple() }
%   {revise_loop, #message{}, pid(), integer(), integer()}
%   { get_deliv, pid() }
%   { return_deliv, q_entries() }
%   { revise_ts, #message{}, pid(), integer(), integer() }
%   { clock_changed, integer() }
%   { final_ts, pid(), integer(), integer() }


%% @doc Starts the UI and gets a node in the ring such that the UI can communicate with the ring. 
%% @see start/0
-spec start() -> no_return().
start() ->
    RingTuple = chat:start().

%% @doc Starts the UI and connects it with the ring. 
%% @see join/1
-spec join(tuple()) -> no_return().
join({GlobalNode, PidString}) ->
    Pid = rpc:call(GlobalNode, erlang, list_to_pid, [PidString]),
    Clock = 0,
    io:format("Welcome to the forum!~n"),
    loop(Pid, Clock).

%% @doc The main loop.
%% @param MasterNode is a node in the ring.
%% @param Clock is the internal clock of the UI.
-spec loop(pid(), integer()) -> no_return().
loop(MasterPid, Clock) ->
    io:format("Your options are: (write number) ~n"),
    io:format("1: List groups ~n"),
    io:format("2: Search group ~n"),
    io:format("3: Search user ~n"),
    io:format("4: Create group ~n"),
    io:format("5: Delete node ~n"),
    io:format("6: Close UI ~n"),
    Term = io:get_line("Choose number: "),
    case Term of
        "1\n" -> group_loop(MasterPid, Clock);
        "2\n" -> group_search_loop(MasterPid, Clock);
        "3\n" -> user_loop(MasterPid, Clock);
        "4\n" ->
            GroupName = string:trim(io:get_line("Groupname for new group: ")),
            N = #node{ key = chat:hash(MasterPid) , pid = MasterPid},
            _NewChannel = chat:start(N, GroupName),
            io:format("Group was created: ~p~n", [GroupName]),
            loop(MasterPid, Clock);
        "5\n" ->
            Pid = list_to_pid(string:trim(io:get_line("Pid: "))),
            Pid ! { exit },
            loop(MasterPid, Clock);
        "6\n" -> exit(kill);
        _ -> 
            io:format("Not an option~n"),
            loop(MasterPid, Clock)
    end.

%% @doc Loop when listing all the groupchats.
%% @param MasterPid is the pid of a node in the ring.
%% @param Clock is the internal clock of the UI.
-spec group_loop(pid(), integer()) -> no_return().
group_loop(MasterPid, Clock) -> 
    MasterPid ! { get_name, self(), MasterPid},
    Channels = list_groups(maps:new()),
    io:format("Here are the different groups avaliable~n"),
    case maps:size(Channels) == 1 of 
        true -> 
            io:format("No groups made ~n"),
            loop(MasterPid, Clock);
        _ ->
            maps:fold(fun(K, _V, ok) ->
                case string:equal(K, "startNode") of 
                    false ->
                        io:format("~p~n", [K]);
                    true -> ok
                end
            end, ok, Channels)
    end,
    Term = io:get_line("Which one would you like to join? (Write \"back\" to return to start) "),
    Group = string:trim(Term),
    case string:equal(Group, "back") of
        true -> 
            io:format("Going back to start~n"),
            loop(MasterPid, Clock);
        _ ->
            JoinedChannel = look_up(Channels, Group),
            case JoinedChannel of
                undefined ->
                    io:format("Group does not exits~n"),
                    group_loop(MasterPid, Clock);
                _ ->
                    Answer = string:trim(io:get_line("Do you want to see the users in the group? (Yes/No) ")),
                    case Answer of 
                        "Yes" -> get_group_users(JoinedChannel);
                        "No" -> ok;
                        _ -> io:format("bad input")
                    end,
                    Username = string:trim(io:get_line("Please choose a username: ")),
                    io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
                    JoinedChannel#node.pid ! {user_joined, Username, self()},
                    init_chat_loop(JoinedChannel, MasterPid, Username, Clock) 
            end
    end.

%% @doc Gets the name of all the groupchats in the ring, which is the nodes.
%% @param Groups is the list the returns are added to.
-spec list_groups(list()) -> list().
list_groups(Groups) ->
  receive
    {return_name, Name, Node} ->
      case maps:is_key(Name, Groups) of 
        true -> Groups;
        _ -> 
          NewGroups = maps:put(Name,Node,Groups),
          list_groups(NewGroups)
        end;
    {done} ->
      Groups
  end.

%% @doc Returns the groupchat node with the given name if it exists in the list of groupchats.
%% @param Grouplist is a list of group-nodes.
%% @param Groupname is the name of the group searched for.
-spec look_up(list(), string()) -> #node{}.
look_up(GroupList, GroupName) ->
  case maps:is_key(GroupName, GroupList) of 
      true -> 
        _Node = maps:get(GroupName,GroupList);
      _ -> 
        undefined
  end.

%% @doc Gets the users in the given groupchat.
%% @param JoinedGroup is the group the users as connected to.
-spec get_group_users(#node{}) -> no_return().
get_group_users(JoinedGroup) ->
    JoinedGroup#node.pid ! {group_users, self()},
    receive
        {return_group_users, Users} ->
            lists:foreach(fun(U) ->
                case U /= undefined of
                    true -> io:format("~p~n", [U]);
                    _ -> ok
                end
            end, Users)
    end.

%% @doc Asks for a group to search for and finds it in the list of groups given by the ring.
%% @param MasterPid is the pid of a node in the ring.
%% @param Clock is the internal clock of the UI.
-spec group_search_loop(pid(), integer()) -> no_return().
group_search_loop(MasterPid, Clock) ->
    Group = string:trim(io:get_line("Group to search for (Write \"back\" to go back) : ")),
    case Group of 
        "back" -> loop(MasterPid, Clock);
        _ -> ok
    end,
    MasterPid ! { get_name, self(), MasterPid},
    Groups = list_groups(maps:new()),
    Node = look_up(Groups, Group),
    case Node of 
        undefined ->
            io:format("Group not found ~n"),
            group_search_loop(MasterPid, Clock);
        _ -> group_found_loop(MasterPid, Node, Group, Clock)
    end.

%% @doc Takes a found group and connects the user to it.
%% @param MasterPid is the pid of a node in the ring.
%% @param Node is the group-node searched for.
%% @param Group is the name of the group searched for.
%% @param Clock is the internal clock of the UI.
-spec group_found_loop(pid(), #node{}, string(), integer()) -> no_return().
group_found_loop(MasterPid, Node, Group, Clock) ->
    Answer = io:get_line("Group found, want to see the users in it? (Yes/No) "),
    case Answer of 
        "Yes\n" -> get_group_users(Node);
        "No\n" -> ok;
        _ -> io:format("bad input")
    end,
    AnswerCon = io:get_line("Want to connect to it? (Yes/No) "),
    case AnswerCon of 
        "Yes\n" -> 
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            Node#node.pid ! {user_joined, Username, self()},
            init_chat_loop(Node, MasterPid, Username, Clock);
        "No\n" ->  
            loop(MasterPid, Clock);
        _ -> 
            io:format("Option no avaliable"),
            group_found_loop(MasterPid, Node, Group, Clock)
    end.

%% @doc Loop for when searching for a user.
%% @param MasterPid is the pid of a node in the ring.
%% @param Clock is the internal clock of the UI.
-spec user_loop(pid(), integer()) -> no_return().
user_loop(MasterPid, Clock) ->
    Name = string:trim(io:get_line("What name would like to search for? ")),
    MasterPid ! { find_user, Name, self(), MasterPid},
    Users = list_users([]),
    io:format("Users found with the name: ~n"),
    case length(Users) == 0 of
        true ->
            io:format("No users by that name ~n");
        _ ->
            lists:foreach(fun(U) ->
                case U /= undefined of
                    true -> io:format("~p~n", [U]);
                    _ -> ok
                end
            end, Users)
    end,
    loop(MasterPid, Clock).

%% @doc Gets all the users in the whole ring, meaning in all groupchats.
%% @param Users is the list the returns are added to.
-spec list_users(list()) -> list().
list_users(Users) ->
    receive
        {return_users, Result} ->
            case Result /= undefined of
                true ->
                    NewUsers = lists:append(Users, [Result]),
                    list_users(NewUsers);
                _ ->
                    list_users(Users)
            end;
        {done} ->
            Users
    end.


%% @doc Loop for when a users is connected to a groupchat, prints the messages already in the groupchat.
%% @param Node is the connected group-node.
%% @param MasterPid is the pid of a node in the ring.
%% @param Username is the users name in the  group.
%% @param Clock is the internal clock of the UI.
-spec init_chat_loop(#node{}, pid(), string(), integer()) -> no_return().
init_chat_loop(Node, MasterPid, Username, Clock) -> 
    io:format("Connected~n"),
    io:format("Type \"quit\" to leave channel. ~n"),
    lists:foreach(fun(U) ->
        io:format("~n~p said: ~p ~n",[U#q_entry.m#message.user#user.name, U#q_entry.m#message.text])
    end, Node#node.messages),
    User = #user{name = Username, pid = self()},
    WaitPid = self(),
    _P = spawn_link(fun() -> write_mess(Node, MasterPid, User, Clock, WaitPid) end),
    _P1 = spawn_link(fun() -> print_messages(WaitPid) end),
    wait_mess(Clock, Node).

%% @doc The loop run such that the user can write messages in a groupchat.
%% @param Node is the connected group-node.
%% @param MasterPid is the pid of a node in the ring.
%% @param User is the users username and pid.
%% @param Clock is the internal clock of the UI.
%% @param WaitPid is the pid of the process handling messages when connected to group.
-spec write_mess(#node{}, pid(), #user{}, integer(), pid()) -> no_return().
write_mess(Node, MasterPid, User, Clock, WaitPid)->
    Message = string:trim(io:get_line(": ")),
    case string:equal(Message, "quit") of
        true -> loop(MasterPid, Clock);
        _ -> 
            NewClock = Clock + 1,
            WaitPid ! {clock_changed, NewClock},
            M = #message{user = User,text = Message},
            Node#node.pid ! {revise_loop, M, self(), erlang:unique_integer([positive]),Clock},
            write_mess(Node, MasterPid, User, NewClock,WaitPid)
    end.

%% @doc Gets the messages sent to the groupchat in intervals and prints them (because of total ordering).
%% @param WaitPid is the pid of the process handling messages when connected to group.
-spec print_messages(pid()) -> no_return().
print_messages(WaitPid) ->
    timer:sleep(?PRINT_INTERVAL),
    WaitPid ! {get_deliv, self()},
    MessageList = receive
        {return_deliv, Deliv_q} -> Deliv_q
    end,
    case length(MessageList) of 
        0 -> print_messages(WaitPid);
        _ ->
            lists:foreach(fun(M) ->
                io:format("~n~p said: ~p ~n",[M#q_entry.m#message.user#user.name, M#q_entry.m#message.text])
            end, MessageList),
            print_messages(WaitPid)
    end.

%% @doc Waits on messages used in the algorithm for total ordering.
%% @param Clock is the internal clock of the UI.
%% @param Node is the connected group-node. 
-spec wait_mess(integer(), #node{}) -> no_return(). 
wait_mess(Clock, Node) ->
    receive
        {get_deliv, ReplyTo} -> 
            ReplyTo ! {return_deliv, Node#node.deliv_q},
            Node#node.pid ! {final_messages, Node#node.deliv_q},
            wait_mess(Clock, Node#node{deliv_q = []});
        {revise_ts, Message, _ReplyTo, Tag, NewClock} ->
            MaxClock = max(Clock, NewClock),
            NewTemp = lists:append(Node#node.temp_q, #q_entry{m = Message, tag = Tag, timestamp = MaxClock, deliverable = false}),
            Node#node.pid ! {proposed_ts, self(), Tag, MaxClock},
            wait_mess(Clock, Node#node{temp_q = NewTemp});
        {clock_changed, ChangedClock} -> wait_mess(ChangedClock, Node);
        {final_ts, _ReplyTo, Tag, Max} -> 
            RecList = [X || X <- [Node#node.temp_q], X#q_entry.tag == Tag],
            NewRec = lists:nth(1, RecList),
            UpdatedRec = NewRec#q_entry{deliverable = true, timestamp = Max}, 
            NewTemp = lists:keyreplace(Tag, #q_entry.tag, [Node#node.temp_q], UpdatedRec),
            SortedTemp = lists:sort(fun(X, Y) -> X#q_entry.timestamp < Y#q_entry.timestamp end, NewTemp),
            FirstEl = lists:nth(1, SortedTemp),
            case FirstEl#q_entry.tag == Tag of 
                true -> 
                    DelEntry = lists:takewhile(fun(Q) -> Q#q_entry.deliverable == true end, SortedTemp),
                    N2 = Node#node{deliv_q = lists:append(Node#node.deliv_q, DelEntry)},
                    NewSortedTemp = lists:nthtail(length(DelEntry), SortedTemp),
                    NewNode = N2#node{temp_q = NewSortedTemp};
                _ -> NewNode = Node
            end,
            wait_mess(Clock, NewNode)
    end.