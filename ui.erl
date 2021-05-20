-module(ui).
-export([start/0]).
% -import(chat,[master_start/0]).
-import_all(chat).

-define(PRINT_INTERVAL,1500).

-type(key() :: non_neg_integer()).
-opaque(users() :: list()).
-opaque(messages() :: list()).
-opaque(q_entries() :: list()).

-record(user, {
    name :: string(),
    pid :: pid()
}).

-record(message, {
    user :: user,
    text :: string()
}).

-record(q_entry,{
  m :: #message{},
  tag :: integer(),
  timestamp :: integer(),
  deliverable :: atom()
}).

% A node is a Channel.
-record(node,{
  name = [] :: string(),
  key :: pid(),
  pid :: key(),
  users = [] :: users(),
  messages = [] :: messages(),
  temp_q = [] :: q_entries(),
  deliv_q = [] :: q_entries()
}).


-define(SLEEP_MIN,2000).

start() ->
    io:format("Welcome to the forum!~n"),
    MasterNode = chat:master_start(),
    io:format("Master: ~p~n", [MasterNode#node.pid]),
    Clock = 0,
    loop(MasterNode, Clock).

%start(MasterNode) ->
%    io:format("Welcome to the forum!~n"),
%    loop(MasterNode).

loop(MasterNode, Clock) ->
    io:format("Your options are: (write number) ~n"),
    io:format("1: List groups ~n"),
    io:format("2: Search group ~n"),
    io:format("3: Search user ~n"),
    io:format("4: Create group ~n"),
    io:format("5: Delete node ~n"),
    Term = io:get_line("Choose number: "),
    case Term of
        "1\n" -> channel_loop(MasterNode, Clock);
        "2\n" -> group_search_loop(MasterNode, Clock);
        "3\n" -> 
            io:format("Not implemented yet ~n"),
            loop(MasterNode, Clock);
        "4\n" ->
            GroupName = io:get_line("Groupname for new group: "),
            TrimGroup = string:trim(GroupName),
            _NewChannel = chat:start(MasterNode, TrimGroup),
            io:format("Group was created: ~p~n", [TrimGroup]),
            loop(MasterNode, Clock);
        "5\n" ->
            Pid = list_to_pid(string:trim(io:get_line("Pid: "))),
            Pid ! { exit },
            loop(MasterNode, Clock);
        _ -> 
            io:format("Not an option~n"),
            loop(MasterNode, Clock)
    end.

group_search_loop(MasterNode, Clock) ->
    Group = io:get_line("Group to search for: "),
    TrimGroup = string:trim(Group),
    MasterNode#node.pid ! { get_name, self(), MasterNode},
    Channels = list_channels(maps:new()),
    Node = look_up(Channels, TrimGroup),
    case node of 
        undefined ->
            io:format("Group not found"),
            group_search_loop(MasterNode, Clock);
        _ -> group_found_loop(MasterNode, Node, TrimGroup, Clock)
    end.

group_found_loop(MasterNode, Node, Group, Clock) ->
    Answer = io:get_line("Group found, want to connect to it? (Yes/No) "),
    case Answer of 
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

list_channels(Channels) ->
  receive
    {return_name, Name, Node} ->
      case maps:is_key(Name, Channels) of 
        true -> Channels;
        _ -> 
          NewChannels = maps:put(Name,Node,Channels),
          list_channels(NewChannels)
        end;
    {done} ->
      Channels
  end.

channel_loop(MasterNode, Clock) -> 
    MasterNode#node.pid ! { get_name, self(), MasterNode},
    Channels = list_channels(maps:new()),
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
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            JoinedChannel = look_up(Channels, Group),
            case JoinedChannel of
                undefined ->
                    io:format("Channels does not exits~n"),
                    channel_loop(MasterNode, Clock);
                _ ->
                    JoinedChannel#node.pid ! {user_joined, Username, self()},
                    init_chat_loop(JoinedChannel, MasterNode, Username, Clock) % Get messages from channel node
            end
    end.

look_up(ChannelList, GroupName) ->
  %io:format("Channels: ~p~n",[Channels]),
  case maps:is_key(GroupName, ChannelList) of 
      true -> 
        _Node = maps:get(GroupName,ChannelList);
      _ -> 
        undefined
  end.

init_chat_loop(Node, MasterNode, Username, Clock) -> % Implement messages right in chat
    io:format("Connected~n"),
    io:format("Type \"quit\" to leave channel. ~n"),
    lists:foreach(fun(U) ->
        io:format("~n~p said: ~p ~n",[U#q_entry.m#message.user#user.name, U#q_entry.m#message.text])
    end, Node#node.messages),
    User = #user{name = Username, pid = self()},
    WaitPid = self(),
    _P = spawn(fun() -> write_mess(Node, MasterNode, User, Clock, WaitPid) end),
    _P1 = spawn(fun() -> print_messages(WaitPid) end),
    %io:format("self inden wait_mess ~p~n", [self()]),
    wait_mess(Clock, Node).

write_mess(Node, MasterNode, User, Clock, WaitPid)->
    Message = io:get_line(": "),
    case string:equal(Message, "quit\n") of
        true -> loop(MasterNode, Clock);
        _ -> 
            NewClock = Clock + 1,
            %io:format("new clock: ~p~n", [NewClock]),
            WaitPid ! {clock_changed, NewClock},
            M = #message{user = User,text = Message},
            Node#node.pid ! {revise_loop, M, self(), erlang:unique_integer([monotonic]),Clock},
            Node#node.pid ! {user_message, User, Message},
            write_mess(Node, MasterNode, User, NewClock,WaitPid)
    end.

print_messages(WaitPid) ->
    timer:sleep(?PRINT_INTERVAL),
    WaitPid ! {get_deliv, self()},
    MessageList = receive
        {return_deliv, Deliv_q} -> Deliv_q
    end,
    case length(MessageList) of 
        0 -> print_messages(WaitPid);
        _ ->
            %io:format("messageList: ~p~n", [MessageList]),
            lists:foreach(fun(M) ->
                io:format("~n~p said: ~p ~n",[M#q_entry.m#message.user#user.name, M#q_entry.m#message.text])
            end, MessageList),
            print_messages(WaitPid)
    end.


wait_mess(Clock, Node) ->
    %io:format("self i wait_mess ~p~n", [self()]),
    receive
        {get_deliv, ReplyTo} -> 
            %io:format("get_deliv"),
            ReplyTo ! {return_deliv, Node#node.deliv_q},
            Node#node.pid ! {final_messages, Node#node.deliv_q},
            wait_mess(Clock, Node#node{deliv_q = []});
        {revise_ts, Message, _ReplyTo, Tag, NewClock} ->
            MaxClock = max(Clock, NewClock),
            NewTemp = lists:append(Node#node.temp_q, #q_entry{m = Message, tag = Tag, timestamp = MaxClock, deliverable = false}),
            Node#node.pid ! {proposed_ts, self(), Tag, MaxClock},
            wait_mess(Clock, Node#node{temp_q = NewTemp});
        {clock_changed, ChangedClock} -> 
            %io:format("Clock changed"),
            wait_mess(ChangedClock, Node);
        {final_ts, _ReplyTo, Tag, Max} -> 
            RecList = [X || X <- [Node#node.temp_q], X#q_entry.tag == Tag],
            %NewRec = lists:keyfind(Tag,#q_entry.tag, Node#node.temp_q),
            NewRec = lists:nth(1, RecList),
            UpdatedRec = NewRec#q_entry{deliverable = true, timestamp = Max}, 
            NewTemp = lists:keyreplace(Tag, #q_entry.tag, [Node#node.temp_q], UpdatedRec),
            SortedTemp = lists:sort(fun(X, Y) -> X#q_entry.timestamp < Y#q_entry.timestamp end, NewTemp),
            FirstEl = lists:nth(1, SortedTemp),
            %io:format("first element: ~p~n", [FirstEl]),
            case FirstEl#q_entry.tag == Tag of 
                true -> 
                    %Node#node{deliv_q = lists:append(Node#node.deliv_q,UpdatedRec)},
                    DelEntry = lists:takewhile(fun(Q) -> Q#q_entry.deliverable == true end, SortedTemp),
                    N2 = Node#node{deliv_q = lists:append(Node#node.deliv_q, DelEntry)},
                    NewSortedTemp = lists:nthtail(length(DelEntry), SortedTemp),
                    NewNode = N2#node{temp_q = NewSortedTemp};
                _ -> NewNode = Node
            end,
            wait_mess(Clock, NewNode)
    end.

% Used for testing
other_person(P) ->
    timer:sleep(?SLEEP_MIN),
    P ! {message, self(), "BRB"}.