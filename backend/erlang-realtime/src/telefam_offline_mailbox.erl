-module(telefam_offline_mailbox).
-behaviour(gen_server).

-export([start_link/0, enqueue/3, drain/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(MAILBOX_ETS, telefam_offline_mailbox_ets).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

enqueue(UserId, MutationId, EncryptedFrame) ->
    gen_server:call(?MODULE, {enqueue, UserId, MutationId, EncryptedFrame}).

drain(UserId, MaxBatch) ->
    gen_server:call(?MODULE, {drain, UserId, MaxBatch}).

init([]) ->
    ets:new(?MAILBOX_ETS, [named_table, ordered_set, private]),
    {ok, #{seq => 0}}.

handle_call({enqueue, UserId, MutationId, Frame}, _From, #{seq := Seq} = State) ->
    NextSeq = Seq + 1,
    ets:insert(?MAILBOX_ETS, {{UserId, NextSeq}, MutationId, Frame, erlang:system_time(millisecond)}),
    {reply, ok, State#{seq := NextSeq}};

handle_call({drain, UserId, MaxBatch}, _From, State) ->
    Matches = ets:match_object(?MAILBOX_ETS, {{UserId, '_'}, '_', '_', '_'}),
    Batch = lists:sublist(Matches, MaxBatch),
    lists:foreach(fun({Key, _, _, _}) -> ets:delete(?MAILBOX_ETS, Key) end, Batch),
    Frames = [{MutId, Frame, Ts} || {_K, MutId, Frame, Ts} <- Batch],
    {reply, {ok, Frames}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
