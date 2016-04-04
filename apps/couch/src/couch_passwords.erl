% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(couch_passwords).

-export([simple/2, pbkdf2/3, pbkdf2/4, verify/2]).
-export([hash_admin_password/1, get_unhashed_admins/0]).

-include("couch_db.hrl").

-define(MAX_DERIVED_KEY_LENGTH, (1 bsl 32 - 1)).
-define(SHA1_OUTPUT_LENGTH, 20).

%% legacy scheme, not used for new passwords.
-spec simple(binary(), binary()) -> binary().
simple(Password, Salt) ->
    list_to_binary(couch_util:to_hex(crypto:hash(sha, <<Password/binary, Salt/binary>>))).

%% CouchDB utility functions
-spec hash_admin_password(binary()) -> binary().
hash_admin_password(ClearPassword) ->
    Iterations = barrel_config:get("couch_httpd_auth", "iterations", "10000"),
    Salt = barrel_uuids:random(),
    DerivedKey = couch_passwords:pbkdf2(couch_util:to_binary(ClearPassword), Salt, list_to_integer(Iterations)),
    list_to_binary("-pbkdf2-" ++ binary_to_list(DerivedKey) ++ ","
        ++ binary_to_list(Salt) ++ ","
        ++ Iterations).

-spec get_unhashed_admins() -> list().
get_unhashed_admins() ->
    lists:filter(
        fun({_User, "-hashed-" ++ _}) ->
            false; % already hashed
        ({_User, "-pbkdf2-" ++ _}) ->
            false; % already hashed
        ({_User, _ClearPassword}) ->
            true
        end, barrel_config:get("admins")).

%% Current scheme, much stronger.
-spec pbkdf2(binary(), binary(), integer()) -> binary().
pbkdf2(Password, Salt, Iterations) ->
    {ok, Result} = pbkdf2(Password, Salt, Iterations, ?SHA1_OUTPUT_LENGTH),
    Result.

-spec pbkdf2(binary(), binary(), integer(), integer())
    -> {ok, binary()} | {error, derived_key_too_long}.
pbkdf2(_Password, _Salt, _Iterations, DerivedLength)
    when DerivedLength > ?MAX_DERIVED_KEY_LENGTH ->
    {error, derived_key_too_long};
pbkdf2(Password, Salt, Iterations, DerivedLength) ->
    L = ceiling(DerivedLength / ?SHA1_OUTPUT_LENGTH),
    <<Bin:DerivedLength/binary,_/binary>> =
        iolist_to_binary(pbkdf2(Password, Salt, Iterations, L, 1, [])),
    {ok, list_to_binary(couch_util:to_hex(Bin))}.

-spec pbkdf2(binary(), binary(), integer(), integer(), integer(), iolist())
    -> iolist().
pbkdf2(_Password, _Salt, _Iterations, BlockCount, BlockIndex, Acc)
    when BlockIndex > BlockCount ->
    lists:reverse(Acc);
pbkdf2(Password, Salt, Iterations, BlockCount, BlockIndex, Acc) ->
    Block = pbkdf2(Password, Salt, Iterations, BlockIndex, 1, <<>>, <<>>),
    pbkdf2(Password, Salt, Iterations, BlockCount, BlockIndex + 1, [Block|Acc]).

-spec pbkdf2(binary(), binary(), integer(), integer(), integer(),
    binary(), binary()) -> binary().
pbkdf2(_Password, _Salt, Iterations, _BlockIndex, Iteration, _Prev, Acc)
    when Iteration > Iterations ->
    Acc;
pbkdf2(Password, Salt, Iterations, BlockIndex, 1, _Prev, _Acc) ->
    InitialBlock = crypto:hmac(sha, Password, <<Salt/binary,BlockIndex:32/integer>>),
    pbkdf2(Password, Salt, Iterations, BlockIndex, 2,
        InitialBlock, InitialBlock);
pbkdf2(Password, Salt, Iterations, BlockIndex, Iteration, Prev, Acc) ->
    Next = crypto:hmac(sha, Password, Prev),
    pbkdf2(Password, Salt, Iterations, BlockIndex, Iteration + 1,
                   Next, crypto:exor(Next, Acc)).

%% verify two lists for equality without short-circuits to avoid timing attacks.
-spec verify(string(), string(), integer()) -> boolean().
verify([X|RestX], [Y|RestY], Result) ->
    verify(RestX, RestY, (X bxor Y) bor Result);
verify([], [], Result) ->
    Result == 0.

-spec verify(binary(), binary()) -> boolean();
            (list(), list()) -> boolean().
verify(<<X/binary>>, <<Y/binary>>) ->
    verify(binary_to_list(X), ?b2l(Y));
verify(X, Y) when is_list(X) and is_list(Y) ->
    case length(X) == length(Y) of
        true ->
            verify(X, Y, 0);
        false ->
            false
    end;
verify(_X, _Y) -> false.

-spec ceiling(number()) -> integer().
ceiling(X) ->
    T = erlang:trunc(X),
    case (X - T) of
        Neg when Neg < 0 -> T;
        Pos when Pos > 0 -> T + 1;
        _ -> T
    end.
