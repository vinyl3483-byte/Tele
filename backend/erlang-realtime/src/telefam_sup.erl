-module(telefam_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 60},
    Children = [
        #{
            id => telefam_rate_limiter,
            start => {telefam_rate_limiter, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [telefam_rate_limiter]
        },
        #{
            id => telefam_offline_mailbox,
            start => {telefam_offline_mailbox, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [telefam_offline_mailbox]
        }
    ],
    {ok, {SupFlags, Children}}.
