-module(ui).
-export([start/0]).
-import(chat,[master_start/0]).

-define(SLEEP_MIN,2000).

start() ->
    io:format("Welcome to the forum!~n"),
    MasterPid = chat:master_start(),
    loop(MasterPid).

loop(MasterPid) ->
    io:format("Your options are: (write number) ~n"),
    io:format("1: List groups ~n"),
    io:format("2: Search group ~n"),
    io:format("3: Search user ~n"),
    io:format("4: Create group ~n"),
    Term = io:get_line("Chose number: "),
    case string:equal(Term, "1\n") of
        true -> channel_loop(MasterPid);
        _ -> 
            case string:equal(Term, "2\n")  of
                true -> 
                    group_search_loop(MasterPid);
                _ -> 
                    case string:equal(Term, "3\n") of
                        true -> 
                            io:format("Not implemented yet ~n"),
                            loop(MasterPid);
                            %User = io:get_line("User to search for: ");
                            % Call to search_user, implement in chat
                        _ -> 
                            case string:equal(Term, "4\n") of
                                true -> 
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
                            end
                    end
            end
    end.

group_search_loop(MasterPid) ->
    Group = io:get_line("Group to search for: "),
    TrimGroup = string:trim(Group),
    MasterPid ! {search_group, self(), TrimGroup},
    receive
        {group_found, undefined, _GroupName} ->
            io:format("Group not found"),
            group_search_loop(MasterPid);
        {group_found, Node, GroupName} ->
            group_found_loop(MasterPid, Node, GroupName)
    end.

group_found_loop(MasterPid, Node, GroupName) ->
    Answer = io:get_line("Group found, want to connect to it? (Yes/No) "),
    case string:equal(Answer, "Yes\n" ) of 
        true -> 
            io:format("Connecting you to: ~p~n", [GroupName]),
            chat_loop(Node, MasterPid);
        _ -> 
            case string:equal(Answer, "No\n") of 
                true -> 
                    loop(MasterPid);
                _ -> 
                    io:format("Option no avaliable"),
                    group_found_loop(MasterPid, Node, GroupName)
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
    Term = io:get_line("Which one would you like to join? (Write back to return to start) "),
    TrimTerm = string:trim(Term),
    case string:equal(TrimTerm, "back") of 
        true -> 
            io:format("Going back to start~n"),
            loop(MasterPid);
        _ ->
            io:format("Connecting you to: ~p~n", [TrimTerm]),
            case maps:is_key(TrimTerm, Channels) of 
                true -> chat_loop(maps:get(TrimTerm, Channels), MasterPid); % Get messages from channel node
                _ -> 
                    io:format("Channels does not exits~n"),
                    channel_loop(MasterPid)
            end
    end.

chat_loop(Node, MasterPid) -> % Implement messages right in chat
    %lists:foreach(fun(N) ->
    %                  io:format("~n~p said: ~p ~n",[self(),N])
    %          end, Node#node.messages),
    io:format("Connected"),
    P = spawn(fun() -> wait_mess() end),
    _P1 = spawn(fun() -> other_person(P) end).
    %write_mess(Node#node.messages).

write_mess(Messages)->
    Mess = io:get_line(": "),
    NewMessages = lists:append(Messages, [Mess]),
    io:format("~n~p said: ~p ~n",[self(),Mess]),
    write_mess(NewMessages).
% Also needs to send message to the channel node

wait_mess() ->
    receive
        {message, Author, Message} -> 
            io:format("~n~p said: ~p  ~n",[Author, Message]),
            wait_mess()
    end.

% Used for testing
other_person(P) ->
    timer:sleep(?SLEEP_MIN),
    P ! {message, self(), "BRB"}.
