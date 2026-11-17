-module(vahvel_build_ffi).
-export([dirs/0, library_names/0, copy/2, loaded_nif_version/0]).

%% {PrivDir, PackageDir}. The runtime loads from PrivDir. Gleam links
%% build/<mode>/erlang/vahvel/priv to the package's priv/ on Unix; PackageDir
%% follows that link, since gleam export wipes build/prod.
dirs() ->
    case code:priv_dir(vahvel) of
        {error, _} ->
            {error, nil};
        Priv ->
            Real =
                case file:read_link_all(Priv) of
                    {ok, Target} -> filename:absname(Target, filename:dirname(Priv));
                    {error, _} -> Priv
                end,
            {ok, {unicode:characters_to_binary(Priv),
                  unicode:characters_to_binary(filename:dirname(Real))}}
    end.

%% {Cargo artifact, name erlang:load_nif expects}; it wants .so on macOS too.
library_names() ->
    case os:type() of
        {win32, _} -> {<<"vahvel.dll">>, <<"vahvel.dll">>};
        {unix, darwin} -> {<<"libvahvel.dylib">>, <<"vahvel.so">>};
        {unix, _} -> {<<"libvahvel.so">>, <<"vahvel.so">>}
    end.

copy(From, To) ->
    case file:copy(From, To) of
        {ok, _} -> {ok, nil};
        {error, Reason} -> {error, unicode:characters_to_binary(file:format_error(Reason))}
    end.

%% Lives outside vahvel_nif: when its on_load fails, that whole module is
%% missing and calls into it raise undef rather than nif_not_loaded.
loaded_nif_version() ->
    try
        {ok, vahvel_nif:nif_version()}
    catch
        error:nif_not_loaded -> {error, nil};
        error:undef -> {error, nil}
    end.
