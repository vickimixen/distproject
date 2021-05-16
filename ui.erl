-module(ui).
-export([start/0, start/1]).
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
    MasterPid = chat:master_start(),
    io:format("Master: ~p~n", [MasterPid]),
    loop(MasterPid).

start(MasterPid) ->
    io:format("Welcome to the forum!~n"),
    loop(MasterPid).

loop(MasterPid) ->
    io:format("Your options are: (write number) ~n"),
    io:format("1: List groups ~n"),
    io:format("2: Search group ~n"),
    io:format("3: Search user ~n"),
    io:format("4: Create group ~n"),
    Term = io:get_line("Choose number: "),
    case Term of
        "1\n" -> channel_loop(MasterPid);
        "2\n" -> group_search_loop(MasterPid);
        "3\n" -> 
            io:format("Not implemented yet ~n"),
            loop(MasterPid);
            %User = io:get_line("User to search for: ");
            % Call to search_user, implement in chat
        "4\n" ->
            GroupName = io:get_line("Groupname for new group: "),
            TrimGroup = string:trim(GroupName),
            MasterPid ! {create_channel, self(), TrimGroup},
            receive
                {group_created, Name} ->
                io:format("Group was created: ~p~n", [Name]),
                loop(MasterPid)
            end;
        _ -> 
            io:format("Not an option~n"),
            loop(MasterPid)
    end.

group_search_loop(MasterPid) ->
    Group = io:get_line("Group to search for: "),
    TrimGroup = string:trim(Group),
    MasterPid ! {search_group, self(), TrimGroup},
    receive
        {group_found, undefined, _GroupName} ->
            io:format("Group not found"),
            group_search_loop(MasterPid);
        {group_found, Node, Group} ->
            group_found_loop(MasterPid, Node, Group)
    end.

group_found_loop(MasterPid, Node, Group) ->
    Answer = io:get_line("Group found, want to connect to it? (Yes/No) "),
    case string:equal(Answer, "Yes\n" ) of 
        true -> 
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            MasterPid ! {join_channel, self(), Username, Group},
            init_chat_loop(Node, MasterPid, Username);
        _ -> 
            case string:equal(Answer, "No\n") of 
                true -> 
                    loop(MasterPid);
                _ -> 
                    io:format("Option no avaliable"),
                    group_found_loop(MasterPid, Node, Group)
            end 
    end.

channel_loop(MasterPid) -> 
    MasterPid ! {list_channels, self()},
    receive
        {list_channels, Channels} -> 
            io:format("Here is the different channels avaliable~n"),
            case maps:size(Channels) == 1 of 
                true -> 
                    io:format("No channels made ~n"),
                    loop(MasterPid);
                _ ->
                    %io:format("~p~n", [Channels]),
                    maps:fold(fun(K, _V, ok) ->
                        case string:equal(K, "startNode") of 
                            false ->
                                io:format("~p~n", [K]);
                            true -> ok
                        end
                    end, ok, Channels)
                    %maps:foreach(fun(Key,_Value) ->
                    %    io:format("~p~n",[Key])
                    %end, Channels)
            end   
    end,
    Term = io:get_line("Which one would you like to join? (Write \"back\" to return to start) "),
    Group = string:trim(Term),
    case string:equal(Group, "back") of
        true -> 
            io:format("Going back to start~n"),
            loop(MasterPid);
        _ ->
            Username = string:trim(io:get_line("Please choose a username: ")),
            io:format("Connecting you to: ~p with the name: ~p~n", [Group, Username]),
            case maps:is_key(Group, Channels) of
                true ->
                    MasterPid ! {join_channel, self(), Username, Group},
                    init_chat_loop(maps:get(Group, Channels), MasterPid, Username); % Get messages from channel node
                _ ->
                    io:format("Channels does not exits~n"),
                    channel_loop(MasterPid)
            end
    end.

init_chat_loop(Node, MasterPid, Username) -> % Implement messages right in chat
    io:format("Connected"),
    lists:foreach(fun(U) ->
        io:format("~n~p said: ~p ~n",[U#message.user#user.name, U#message.text])
    end, Node#node.messages),
    User = #user{name = Username, pid = self()},
    io:format("Type \"quit\" to leave channel. ~n"),
    P = spawn(fun() -> write_mess(Node, MasterPid, User) end),
    wait_mess().

write_mess(Node, MasterPid, User)->
    Message = io:get_line(": "),
    case string:equal(Message, "quit\n") of
        true -> loop(MasterPid);
        _ -> 
            Node#node.pid ! {user_message, User, Message},
            write_mess(Node, MasterPid, User)
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