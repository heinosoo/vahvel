-module(vahvel_nif).
-on_load(init/0).
-export([init/0, nif_version/0, nif_version_result/0, driver_solve/2, driver_evaluate/2]).

init() ->
    SoName = code:priv_dir(vahvel) ++ "/vahvel",
    erlang:load_nif(SoName, 0).

nif_version() ->
    erlang:nif_error(nif_not_loaded).

nif_version_result() ->
    try
        {ok, nif_version()}
    catch
        error:nif_not_loaded -> {error, nil}
    end.

driver_solve(_Model, _Limits) ->
    erlang:nif_error(nif_not_loaded).

driver_evaluate(_Expression, _Values) ->
    erlang:nif_error(nif_not_loaded).
