-module(nif).
-on_load(init/0).
-export([
    init/0,
    nif_version/0, nif_version_result/0,
    solve_linear_system/4, transpose/3,
    matrix_add/4, matrix_subtract/4, matrix_scale/4, matrix_multiply/6,
    matrix_determinant/2, matrix_inverse/2,
    matrix_lu/2, matrix_qr/3, matrix_svd/3, matrix_symmetric_eigenvalues/2,
    random_uniform/4, random_uniform_seeded/5,
    random_normal/4, random_normal_seeded/5,
    random_bernoulli/3, random_bernoulli_seeded/4
]).

init() ->
    SoName = code:priv_dir(waffle) ++ "/waffle",
    erlang:load_nif(SoName, 0).

%% NIF stubs
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

solve_linear_system(_Rows, _Cols, _A, _B) ->
    erlang:nif_error(nif_not_loaded).

transpose(_Rows, _Cols, _Data) ->
    erlang:nif_error(nif_not_loaded).

matrix_add(_Rows, _Cols, _A, _B) ->
    erlang:nif_error(nif_not_loaded).

matrix_subtract(_Rows, _Cols, _A, _B) ->
    erlang:nif_error(nif_not_loaded).

matrix_scale(_Rows, _Cols, _Data, _Scalar) ->
    erlang:nif_error(nif_not_loaded).

matrix_multiply(_ARows, _ACols, _A, _BRows, _BCols, _B) ->
    erlang:nif_error(nif_not_loaded).

matrix_determinant(_N, _Data) ->
    erlang:nif_error(nif_not_loaded).

matrix_inverse(_N, _Data) ->
    erlang:nif_error(nif_not_loaded).

matrix_lu(_N, _Data) ->
    erlang:nif_error(nif_not_loaded).

matrix_qr(_Rows, _Cols, _Data) ->
    erlang:nif_error(nif_not_loaded).

matrix_svd(_Rows, _Cols, _Data) ->
    erlang:nif_error(nif_not_loaded).

matrix_symmetric_eigenvalues(_N, _Data) ->
    erlang:nif_error(nif_not_loaded).

random_uniform(_Rows, _Cols, _Min, _Max) ->
    erlang:nif_error(nif_not_loaded).

random_uniform_seeded(_Rows, _Cols, _Min, _Max, _Seed) ->
    erlang:nif_error(nif_not_loaded).

random_normal(_Rows, _Cols, _Mean, _StdDev) ->
    erlang:nif_error(nif_not_loaded).

random_normal_seeded(_Rows, _Cols, _Mean, _StdDev, _Seed) ->
    erlang:nif_error(nif_not_loaded).

random_bernoulli(_Rows, _Cols, _P) ->
    erlang:nif_error(nif_not_loaded).

random_bernoulli_seeded(_Rows, _Cols, _P, _Seed) ->
    erlang:nif_error(nif_not_loaded).
