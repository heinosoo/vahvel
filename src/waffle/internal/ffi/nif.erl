-module(nif).
-on_load(init/0).
-export([init/0, nif_version/0, nif_version_result/0, driver_solve/1]).

init() ->
    SoName = code:priv_dir(waffle) ++ "/waffle",
    erlang:load_nif(SoName, 0).

nif_version() ->
    erlang:nif_error(nif_not_loaded).

nif_version_result() ->
    try
        {ok, nif_version()}
    catch
        error:nif_not_loaded -> {error, nil}
    end.

driver_solve(_Model) ->
    erlang:nif_error(nif_not_loaded).
