-module(ui).
-export([start/0]).
% -import(chat,[master_start/0]).
-import_all(chat).

-define(PRINT_INTERVAL,1500).
-define(SLEEP_MIN,2000).

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
  messages = [] :: messages(),
  temp_q = [] :: q_entries(),
  deliv_q = [] :: q_entries()
}).

% All Messages
%   { return_name, string(), node{} }
%   { done }
%   { return_group_users, users() }
%   { find_user, string(), pid(), node{} }
%   { return_users, tuple() }
%   {revise_loop, message{}, pid(), integer(), integer()}
%   { get_deliv, pid() }
%   { return_deliv, q_entries() }
%   { revise_ts, message{}, pid(), integer(), integer() }
%   { clock_changed, integer() }
%   { final_ts, pid(), integer(), integer() }


%Starts the UI and gets a node in the ring such that the UI can communicate with the ring 
start() ->
    io:format("Welcome to the forum!~n"),
    MasterNode = chat:master_start(),
    io:format("Master: ~p~n", [MasterNode#node.pid]),
    Clock = 0,
    loop(MasterNode, Clock).

%start(MasterNode) ->
%    io:format("Welcome to the forum!~n"),
%    loop(MasterNode).

% The main loop
loop(MasterNode, Clock) ->
    io:format("Your options are: (write number) ~n"),
    io:format("1: List groups ~n"),
    io:format("2: Search group ~n"),
    io:format("3: Search user ~n"),
    io:format("4: Create group ~n"),
    io:format("5: Delete node ~n"),
    Term = io:get_line("Choose number: "),
    case Term of
        "1\n" -> group_loop(MasterNode, Clock);
        "2\n" -> group_search_loop(MasterNode, Clock);
        "3\n" -> user_loop(MasterNode, Clock);
        "4\n" ->
            GroupName = string:trim(io:get_line("Groupname for new group: ")),
            _NewChannel = chat:start(MasterNode, GroupName),
            io:format("Group was created: ~p~n", [GroupName]),
            loop(MasterNode, Clock);
        "5\n" ->
            Pid = list_to_pid(string:trim(io:get_line("Pid: "))),
            Pid ! { exit },
            loop(MasterNode, Clock);
        _ -> 
            io:format("Not an option~n"),
            loop(MasterNode, Clock)
    end.

% Loop when listing all the groupchats
group_loop(MasterNode, Clock) -> 
    MasterNode#node.pid ! { get_name, self(), MasterNode},
    Channels = list_groups(maps:new()),
    io:format("Here is the different channels avaliable~n"),
    case maps:size(Channels) == 1 of 
        true -> 
            io:format("No channels made ~n"),
            loop(MasterNode, Clock);
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
            loop(MasterNode, Clock);
        _ ->
            Answer = string:trim(io:get_line("Do you want to see the users in the group? (Yes/No) ")),
            JoinedChannel = look_up(Channels, Group),
            case Answer of 
                "Yes" -> get_group_users(JoinedChannel);
                "No" -> ok
            end,
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            case JoinedChannel of
                undefined ->
                    io:format("Channels does not exits~n"),
                    group_loop(MasterNode, Clock);
                _ ->
                    JoinedChannel#node.pid ! {user_joined, Username, self()},
                    init_chat_loop(JoinedChannel, MasterNode, Username, Clock) 
            end
    end.

% Gets the name of all the groupchats in the ring, which is the nodes
list_groups(Channels) ->
  receive
    {return_name, Name, Node} ->
      case maps:is_key(Name, Channels) of 
        true -> Channels;
        _ -> 
          NewChannels = maps:put(Name,Node,Channels),
          list_groups(NewChannels)
        end;
    {done} ->
      Channels
  end.

% Returns the groupchat name given as parameter if it exists in the list of groupchats given as parameter
look_up(GroupList, GroupName) ->
  case maps:is_key(GroupName, GroupList) of 
      true -> 
        _Node = maps:get(GroupName,GroupList);
      _ -> 
        undefined
  end.

% Gets the users in the given groupchat
get_group_users(JoinedChannel) ->
    JoinedChannel#node.pid ! {group_users, self()},
    receive
        {return_group_users, Users} ->
            lists:foreach(fun(U) ->
                case U /= undefined of
                    true -> io:format("~p~n", [U]);
                    _ -> ok
                end
            end, Users)
    end.

% Asks for a group to seach for and finds it in the list of goups given by the ring
group_search_loop(MasterNode, Clock) ->
    Group = string:trim(io:get_line("Group to search for: ")),
    MasterNode#node.pid ! { get_name, self(), MasterNode},
    Groups = list_groups(maps:new()),
    Node = look_up(Groups, Group),
    case Node of 
        undefined ->
            io:format("Group not found"),
            group_search_loop(MasterNode, Clock);
        _ -> group_found_loop(MasterNode, Node, Group, Clock)
    end.

% Takes a found group and connects the user to it
group_found_loop(MasterNode, Node, Group, Clock) ->
    Answer = io:get_line("Group found, want to see the users in it? (Yes/No) "),
    case Answer of 
        "Yes\n" -> get_group_users(Node);
        "No\n" -> ok
    end,
    AnswerCon = io:get_line("Want to connect to it? (Yes/No) "),
    case AnswerCon of 
        "Yes\n" -> 
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            Node#node.pid ! {user_joined, Username, self()},
            init_chat_loop(Node, MasterNode, Username, Clock);
        "No\n" ->  
            loop(MasterNode, Clock);
        _ -> 
            io:format("Option no avaliable"),
            group_found_loop(MasterNode, Node, Group, Clock)
    end.

% Loop for when searching for a user
user_loop(MasterNode, Clock) ->
    Name = string:trim(io:get_line("What name would like to search for? ")),
    MasterNode#node.pid ! { find_user, Name, self(), MasterNode},
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
    loop(MasterNode, Clock).

% Gets all the users in the whole ring, meaning in all groupchats
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


% Loop for when a users is connected to a groupchat, prints the messages alrady in the groupchat
init_chat_loop(Node, MasterNode, Username, Clock) -> 
    io:format("Connected~n"),
    io:format("Type \"quit\" to leave channel. ~n"),
    lists:foreach(fun(U) ->
        io:format("~n~p said: ~p ~n",[U#q_entry.m#message.user#user.name, U#q_entry.m#message.text])
    end, Node#node.messages),
    User = #user{name = Username, pid = self()},
    WaitPid = self(),
    _P = spawn(fun() -> write_mess(Node, MasterNode, User, Clock, WaitPid) end),
    _P1 = spawn(fun() -> print_messages(WaitPid) end),
    wait_mess(Clock, Node).

% The loop run such that the user can write messages in a groupchat
write_mess(Node, MasterNode, User, Clock, WaitPid)->
    Message = io:get_line(": "),
    case string:equal(Message, "quit\n") of
        true -> loop(MasterNode, Clock);
        _ -> 
            NewClock = Clock + 1,
            WaitPid ! {clock_changed, NewClock},
            M = #message{user = User,text = Message},
            Node#node.pid ! {revise_loop, M, self(), erlang:unique_integer([monotonic]),Clock},
            write_mess(Node, MasterNode, User, NewClock,WaitPid)
    end.

% Gets the messages sent to the groupchat in intervals and prints them (because of total ordering)
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

% Waits on messages used in the algorithm for total ordering
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