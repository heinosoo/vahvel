-module(nif).
-on_load(init/0).
-export([init/0, solve_linear_system/4, nif_version/0, nif_version_result/0, transpose/3]).

init() ->
    SoName = code:priv_dir(waffle) ++ "/waffle",
    erlang:load_nif(SoName, 0).

%% NIF stubs
solve_linear_system(_Rows, _Cols, _A, _B) ->
    erlang:nif_error(nif_not_loaded).

nif_version() ->
    erlang:nif_error(nif_not_loaded).

%% Safe wrapper that returns {ok, Version} or {error, nil}
nif_version_result() ->
    try
        {ok, nif_version()}
    catch
        error:nif_not_loaded ->
            {error, nil}
    end.

transpose(_Rows, _Cols, _Data) ->
    erlang:nif_error(nif_not_loaded).
