-module(ui).
-export([start/0]).
% -import(chat,[master_start/0]).
-import_all(chat).

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

% A node is a Channel.
-record(node,{
  name = [] :: string(),
  key :: pid(),
  pid :: key(),
  users = [] :: users(),
  messages = [] :: messages()
}).

-define(SLEEP_MIN,2000).

start() ->
    io:format("Welcome to the forum!~n"),
    MasterNode = chat:master_start(),
    io:format("Master: ~p~n", [MasterNode#node.pid]),
    loop(MasterNode).

%start(MasterNode) ->
%    io:format("Welcome to the forum!~n"),
%    loop(MasterNode).

loop(MasterNode) ->
    io:format("Your options are: (write number) ~n"),
    io:format("1: List groups ~n"),
    io:format("2: Search group ~n"),
    io:format("3: Search user ~n"),
    io:format("4: Create group ~n"),
    Term = io:get_line("Choose number: "),
    case Term of
        "1\n" -> channel_loop(MasterNode);
        "2\n" -> group_search_loop(MasterNode);
        "3\n" -> 
            io:format("Not implemented yet ~n"),
            loop(MasterNode);
        "4\n" ->
            GroupName = io:get_line("Groupname for new group: "),
            TrimGroup = string:trim(GroupName),
            _NewChannel = chat:start(MasterNode, TrimGroup),
            io:format("Group was created: ~p~n", [TrimGroup]),
            loop(MasterNode);

        _ -> 
            io:format("Not an option~n"),
            loop(MasterNode)
    end.

group_search_loop(MasterNode) ->
    Group = io:get_line("Group to search for: "),
    TrimGroup = string:trim(Group),
    MasterNode#node.pid ! { get_name, self(), MasterNode},
    Channels = list_channels(maps:new()),
    Node = look_up(Channels, TrimGroup),
    case node of 
        undefined ->
            io:format("Group not found"),
            group_search_loop(MasterNode);
        _ -> group_found_loop(MasterNode, Node, TrimGroup)
    end.

group_found_loop(MasterNode, Node, Group) ->
    Answer = io:get_line("Group found, want to connect to it? (Yes/No) "),
    case Answer of 
        "Yes\n" -> 
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            Node#node.pid ! {user_joined, Username, self()},
            init_chat_loop(Node, MasterNode, Username);
        "No\n" ->  
            loop(MasterNode);
        _ -> 
            io:format("Option no avaliable"),
            group_found_loop(MasterNode, Node, Group)
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

channel_loop(MasterNode) -> 
    MasterNode#node.pid ! { get_name, self(), MasterNode},
    Channels = list_channels(maps:new()),
    io:format("Here is the different channels avaliable~n"),
    case maps:size(Channels) == 1 of 
        true -> 
            io:format("No channels made ~n"),
            loop(MasterNode);
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
            loop(MasterNode);
        _ ->
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            JoinedChannel = look_up(Channels, Group),
            case JoinedChannel of
                undefined ->
                    io:format("Channels does not exits~n"),
                    channel_loop(MasterNode);
                _ ->
                    JoinedChannel#node.pid ! {user_joined, Username, self()},
                    init_chat_loop(JoinedChannel, MasterNode, Username) % Get messages from channel node
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

init_chat_loop(Node, MasterNode, Username) -> % Implement messages right in chat
    io:format("Connected"),
    lists:foreach(fun(U) ->
        io:format("~n~p said: ~p ~n",[U#message.user#user.name, U#message.text])
    end, Node#node.messages),
    User = #user{name = Username, pid = self()},
    io:format("Type \"quit\" to leave channel. ~n"),
    _P = spawn(fun() -> write_mess(Node, MasterNode, User) end),
    wait_mess().

write_mess(Node, MasterNode, User)->
    Message = io:get_line(": "),
    case string:equal(Message, "quit\n") of
        true -> loop(MasterNode);
        _ -> 
            Node#node.pid ! {user_message, User, Message},
            write_mess(Node, MasterNode, User)
    end.

wait_mess() ->
    receive
        {new_message, MessageRecord} -> 
            io:format("~n~p said: ~p ~n",[MessageRecord#message.user#user.name, MessageRecord#message.text]),
            wait_mess()
    end.

% Used for testing
other_person(P) ->
    timer:sleep(?SLEEP_MIN),
    P ! {message, self(), "BRB"}.