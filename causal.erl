

-record(message, {
	user :: user,
	text :: string()
}).

-record(Q_entry,{
  m :: #message{},
  tag :: int(),
  timestamp :: int(),
  deliverable :: atom()
}).

loop()