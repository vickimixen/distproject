# Final Project

> erl -make

## If wanted to run in multiple terminals

> erl -sname "name"  

This is done for each terminal all with unique names.

## In one of the terminals

> T = ui:start().

The terminal will print something like this:  
> {'2@LAPTOP-91UN0LD8',"<0.86.0>"}

## If in same terminal as ui:start() was run then write:  
> ui:join(T).

## else:  
> ui:join({'2@LAPTOP-91UN0LD8',"<0.86.0>"}).

## After the last commands the UI runs, there are 6 possibilies:

1: List groups   
2: Search group  
3: Search user  
4: Create group  
5: Delete node
6: Close UI

To select the option write the number associated with the option you want.  
Throughout the UI it is written what you can do. 