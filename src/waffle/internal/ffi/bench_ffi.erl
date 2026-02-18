-module(bench_ffi).
-export([monotonic_time_ns/0, argv/0]).

monotonic_time_ns() -> erlang:monotonic_time(nanosecond).

argv() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].
