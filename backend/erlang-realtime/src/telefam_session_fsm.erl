-module(telefam_session_fsm).
-behaviour(gen_statem).

-export([start_link/2, notify_heartbeat/1, notify_weak_link/1, notify_disconnect/1, send_frame/3]).
-export([callback_mode/0, init/1, online/3, weak_network/3, offline/3, terminate/3]).

-record(data, {
    user_id :: binary(),
    device_fp :: binary(),
    missed_pings = 0 :: non_neg_integer()
}).

start_link(UserId, DeviceFP) ->
    gen_statem:start_link(?MODULE, [UserId, DeviceFP], []).

notify_heartbeat(Pid) ->
    gen_statem:cast(Pid, heartbeat).

notify_weak_link(Pid) ->
    gen_statem:cast(Pid, weak_link).

notify_disconnect(Pid) ->
    gen_statem:cast(Pid, disconnect).

send_frame(Pid, MutationId, EncryptedFrame) ->
    gen_statem:call(Pid, {send_frame, MutationId, EncryptedFrame}).

callback_mode() -> state_functions.

init([UserId, DeviceFP]) ->
    {ok, online, #data{user_id = UserId, device_fp = DeviceFP}, [{state_timeout, 30000, check_link}]}.

online(cast, heartbeat, Data) ->
    {keep_state, Data#data{missed_pings = 0}, [{state_timeout, 30000, check_link}]};
online(cast, weak_link, Data) ->
    {next_state, weak_network, Data, [{state_timeout, 45000, check_link}]};
online(cast, disconnect, Data) ->
    {next_state, offline, Data};
online(state_timeout, check_link, #data{missed_pings = M} = Data) when M >= 1 ->
    {next_state, weak_network, Data#data{missed_pings = M + 1}, [{state_timeout, 45000, check_link}]};
online(state_timeout, check_link, #data{missed_pings = M} = Data) ->
    {keep_state, Data#data{missed_pings = M + 1}, [{state_timeout, 30000, check_link}]};
online({call, From}, {send_frame, MutId, Frame}, Data) ->
    {ok, Buffered} = telefam_offline_mailbox:drain(Data#data.user_id, 25),
    {keep_state, Data, [{reply, From, {delivered, [{MutId, Frame} | [{M, F} || {M, F, _} <- Buffered]]}}]}.

weak_network(cast, heartbeat, Data) ->
    {next_state, online, Data#data{missed_pings = 0}, [{state_timeout, 30000, check_link}]};
weak_network(cast, disconnect, Data) ->
    {next_state, offline, Data};
weak_network(state_timeout, check_link, Data) ->
    {next_state, offline, Data};
weak_network({call, From}, {send_frame, MutId, Frame}, Data) ->
    %% Small adaptive batch size under weak network
    {ok, Buffered} = telefam_offline_mailbox:drain(Data#data.user_id, 4),
    {keep_state, Data, [{reply, From, {delivered_weak, [{MutId, Frame} | [{M, F} || {M, F, _} <- Buffered]]}}]}.

offline(cast, heartbeat, Data) ->
    {next_state, online, Data#data{missed_pings = 0}, [{state_timeout, 30000, check_link}]};
offline({call, From}, {send_frame, MutId, Frame}, Data) ->
    ok = telefam_offline_mailbox:enqueue(Data#data.user_id, MutId, Frame),
    {keep_state, Data, [{reply, From, queued_offline}]};
offline(_Type, _Event, Data) ->
    {keep_state, Data}.

terminate(_Reason, _State, _Data) ->
    ok.
