-module(vahvel_nif).
-on_load(init/0).
-export([init/0, nif_version/0, driver_solve/2, driver_evaluate/2]).

init() ->
    case 'vahvel@internal@build':ensure_built() of
        {ok, nil} ->
            erlang:load_nif(code:priv_dir(vahvel) ++ "/vahvel", 0);
        {error, Message} ->
            io:format(standard_error,
                      "vahvel: ~ts~nvahvel: fix the cause, then run `gleam run -m vahvel/setup`~n",
                      [Message]),
            {error, Message}
    end.

nif_version() ->
    erlang:nif_error(nif_not_loaded).

driver_solve(_Model, _Limits) ->
    erlang:nif_error(nif_not_loaded).

driver_evaluate(_Expression, _Values) ->
    erlang:nif_error(nif_not_loaded).
