-module(platform).
-export([os_family/0]).

os_family() ->
    {Family, _Name} = os:type(),
    atom_to_binary(Family, utf8).
