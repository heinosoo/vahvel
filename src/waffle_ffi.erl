-module(waffle_ffi).
-on_load(init/0).
-export([add_floats/2, init/0]).

init() ->
    SoName = code:priv_dir(waffle) ++ "/waffle",
    erlang:load_nif(SoName, 0).

add_floats(_A, _B) ->
    erlang:nif_error(nif_not_loaded).