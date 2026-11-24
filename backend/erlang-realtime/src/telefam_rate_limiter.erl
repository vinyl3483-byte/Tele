-module(telefam_rate_limiter).
-behaviour(gen_server).

-export([start_link/0, allow_request/3, check_and_advance_otp_cooldown/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RATE_TABLE, telefam_rate_ets).
-define(COOLDOWN_TABLE, telefam_otp_cooldown_ets).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

allow_request(AccountHash, DeviceFP, IpFP) ->
    gen_server:call(?MODULE, {allow_request, AccountHash, DeviceFP, IpFP}).

check_and_advance_otp_cooldown(AccountHash, DeviceFP) ->
    gen_server:call(?MODULE, {otp_cooldown, AccountHash, DeviceFP}).

init([]) ->
    ets:new(?RATE_TABLE, [named_table, set, private]),
    ets:new(?COOLDOWN_TABLE, [named_table, set, private]),
    erlang:send_after(60000, self(), prune_expired),
    {ok, #{}}.

handle_call({allow_request, Acc, Dev, Ip}, _From, State) ->
    Now = erlang:system_time(second),
    Allowed = check_bucket({acc, Acc}, Now, 8, 60) andalso
              check_bucket({dev, Dev}, Now, 25, 60) andalso
              check_bucket({ip, Ip}, Now, 40, 60),
    {reply, Allowed, State};

handle_call({otp_cooldown, Acc, Dev}, _From, State) ->
    Now = erlang:system_time(second),
    Key = {Acc, Dev},
    case ets:lookup(?COOLDOWN_TABLE, Key) of
        [{Key, Count, BlockedUntil, _LastSent}] when BlockedUntil > Now ->
            {reply, {cooldown_active, BlockedUntil - Now, Count}, State};
        [{Key, PrevCount, _BlockedUntil, LastSent}] ->
            NextCount = case Now - LastSent > 86400 of
                true -> 1;
                false -> PrevCount + 1
            end,
            Dur = cooldown_seconds(NextCount),
            ets:insert(?COOLDOWN_TABLE, {Key, NextCount, Now + Dur, Now}),
            {reply, {ok, Dur, NextCount}, State};
        [] ->
            Dur = cooldown_seconds(1),
            ets:insert(?COOLDOWN_TABLE, {Key, 1, Now + Dur, Now}),
            {reply, {ok, Dur, 1}, State}
    end;

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(prune_expired, State) ->
    Now = erlang:system_time(second),
    ets:foldl(fun({K, Timestamps}, _) ->
        Filtered = [T || T <- Timestamps, Now - T < 120],
        case Filtered of
            [] -> ets:delete(?RATE_TABLE, K);
            _ -> ets:insert(?RATE_TABLE, {K, Filtered})
        end
    end, ok, ?RATE_TABLE),
    erlang:send_after(60000, self(), prune_expired),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

check_bucket(Key, Now, Limit, Window) ->
    Existing = case ets:lookup(?RATE_TABLE, Key) of
        [{Key, List}] -> [T || T <- List, Now - T < Window];
        [] -> []
    end,
    case length(Existing) >= Limit of
        true ->
            ets:insert(?RATE_TABLE, {Key, Existing}),
            false;
        false ->
            ets:insert(?RATE_TABLE, {Key, [Now | Existing]}),
            true
    end.

cooldown_seconds(Count) when Count =< 3 -> 60;
cooldown_seconds(4) -> 900;
cooldown_seconds(5) -> 3600;
cooldown_seconds(_) -> 86400.
