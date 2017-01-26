%% Copyright 2016, Bernard Notarianni
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

-module(barrel_http_rest_db).
-author("Bernard Notarianni").

-export([init/3]).
-export([handle/2]).
-export([terminate/3]).

-export([trails/0]).

trails() ->
  Metadata =
    #{ get => #{ summary => "Get the database informations"
               , produces => ["application/json"]
               , parameters =>
                   [#{ name => <<"store">>
                     , description => <<"Store ID">>
                     , in => <<"path">>
                     , required => true
                     , type => <<"string">>}
                   ]
               },
      put => #{ summary => "Create a new database"
        , produces => ["application/json"]
        , parameters =>
        [#{ name => <<"dbid">>
          , description => <<"Database ID">>
          , in => <<"path">>
          , required => true
          , type => <<"string">>}
        ]
      },
      delete => #{ summary => "Delete a database"
        , produces => ["application/json"]
        , parameters =>
        [#{ name => <<"dbid">>
          , description => <<"Database ID">>
          , in => <<"path">>
          , required => true
          , type => <<"string">>}
        ]
      }
    },
  [trails:trail("/:store", ?MODULE, [], Metadata)].

-record(state, {method, store}).

init(_Type, Req, []) ->
  {ok, Req, #state{}}.

handle(Req, State) ->
  {Method, Req2} = cowboy_req:method(Req),
  route(Req2, State#state{method=Method}).

terminate(_Reason, _Req, _State) ->
  ok.

route(Req, #state{method= <<"HEAD">>}=State) ->
  {Store, Req2} = cowboy_req:binding(store, Req),
  case barrel_http_lib:has_store(Store) of
    true ->
      barrel_http_reply:json(200, <<>>, Req2, State);
    false ->
      barrel_http_reply:error(404, <<>>, Req2, State)
  end;
route(Req, #state{method= <<"GET">>}=State) ->
  check_store_exist(Req, State);
route(Req, #state{method= <<"PUT">>}=State) ->
  {Store, Req2} = cowboy_req:binding(store, Req),
  case barrel:create_db(Store, #{}) of
    {ok, _} ->
      barrel_http_reply:json(200, #{ ok => true }, Req2, State);
    {error, db_exists} ->
      barrel_http_reply:error(409, "db exists", Req2, State);
    Error ->
      lager:error("got server error ~p~n", [Error]),
      barrel_http_reply:error(500, "db error", Req2, State)
  end;
route(Req, #state{method= <<"DELETE">>}=State) ->
  {Store, Req2} = cowboy_req:binding(store, Req),
  ok = barrel:delete_db(Store),
  barrel_http_reply:json(200, #{ ok => true }, Req2, State);
route(Req, #state{method= <<"POST">>}) ->
  barrel_http_rest_doc:handle_post(Req);
route(Req, State) ->
  barrel_http_reply:error(405, Req, State).

check_store_exist(Req, State) ->
  {Store, Req2} = cowboy_req:binding(store, Req),
  case barrel_http_lib:has_store(Store) of
    true ->
      get_resource(Req2, State#state{store=Store});
    false ->
      barrel_http_reply:error(404, "store not found", Req2, State)
  end.

get_resource(Req, #state{store=Store}=State) ->
  barrel_http_reply:doc(barrel:db_infos(Store), Req, State).
