-module(waffle_ffi).
-on_load(init/0).
-export([add_floats/2, init/0, float_to_bytes/1, bytes_to_float/1, solve_linear_system/4]).

init() ->
    SoName = code:priv_dir(waffle) ++ "/waffle",
    erlang:load_nif(SoName, 0).

add_floats(_A, _B) ->
    erlang:nif_error(nif_not_loaded).

float_to_bytes(F) when is_float(F) ->
    <<F:64/little-float>>.

bytes_to_float(<<F:64/little-float>>) ->
    F.

solve_linear_system(_Rows, _Cols, _A, _B) ->
    erlang:nif_error(nif_not_loaded).
