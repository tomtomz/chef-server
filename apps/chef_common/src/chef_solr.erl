%
% License:: Apache License, Version 2.0
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
%     http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%
% @author John Keiser <jkeiser@opscode.com>
% @copyright Copyright 2011 Opscode, Inc.
% @version 0.0.1
% @doc Helper module for calling various Chef REST endpoints
% @end
-module(chef_solr).

-export([search/1, make_query_from_params/1, add_org_guid_to_query/2]).

-include_lib("webmachine/include/webmachine.hrl").
-include("chef_solr.hrl").

make_query_from_params(Req) ->
    % TODO: super awesome error messages
    % TODO: verify that FilterQuery, Start, Rows and Sort have correct values
    ObjType = wrq:path_info(object_type, Req),
    QueryString = case wrq:get_qs_value("q", Req) of
                      undefined ->
                          "*:*";                % default query string
                      Query ->
                          transform_query(http_uri:decode(Query))
                  end,
    FilterQuery = make_fq_type(ObjType),
    Start = decode(nonneg_int, "start", Req, 0),
    Rows = decode(nonneg_int, "rows", Req, 1000),
    %% 'sort' param is ignored and hardcoded because indexing
    %% scheme doesn't support sorting since there is only one field.
    Sort = "X_CHEF_id_CHEF_X asc",
    #chef_solr_query{query_string = QueryString,
                     filter_query = FilterQuery,
                     start = Start,
                     rows = Rows,
                     sort = Sort,
                     index = index_type(ObjType)}.

decode(nonneg_int, Key, Req, Default) ->
    {Int, Orig} =
        case wrq:get_qs_value(Key, Req) of
            undefined ->
                {Default, default};
            Value ->
                try
                    {list_to_integer(http_uri:decode(Value)), Value}
                catch
                    error:badarg ->
                        throw({bad_param, {Key, Value}})
                end
        end,
    validate_non_neg(Key, Int, Orig).

validate_non_neg(Key, Int, OrigValue) when Int < 0 ->
    throw({bad_param, {Key, OrigValue}});
validate_non_neg(_Key, Int, _OrigValue) ->
    Int.

-spec add_org_guid_to_query(#chef_solr_query{}, binary()) ->
                                   #chef_solr_query{}.
add_org_guid_to_query(Query = #chef_solr_query{filter_query = FilterQuery},
                      OrgGuid) ->
    Query#chef_solr_query{filter_query = "+X_CHEF_database_CHEF_X:chef_" ++
                              binary_to_list(OrgGuid) ++ " " ++ FilterQuery}.

search(Query) ->
    {ok, SolrUrl} = application:get_env(chef_common, solr_url),
    Url = SolrUrl ++ make_solr_query_url(Query),
    % FIXME: error handling
    {ok, _Code, _Head, Body} = ibrowse:send_req(Url, [], get),
    SolrData = ejson:decode(Body),
    Response = ej:get({<<"response">>}, SolrData),
    Start = ej:get({<<"start">>}, Response),
    NumFound = ej:get({<<"numFound">>}, Response),
    DocList = ej:get({<<"docs">>}, Response),
    Ids = [ ej:get({<<"X_CHEF_id_CHEF_X">>}, Doc) || Doc <- DocList ],
    { ok, Start, NumFound, Ids }.

transform_query(RawQuery) when is_list(RawQuery) ->
    transform_query(list_to_binary(RawQuery));
transform_query(RawQuery) ->
    case chef_lucene:parse(RawQuery) of
        Query when is_binary(Query) ->
            binary_to_list(Query);
        _ ->
            throw({bad_query, RawQuery})
    end.


%% Internal functions

% /solr/select?
    % fq=%2BX_CHEF_type_CHEF_X%3Anode+%2BX_CHEF_database_CHEF_X%3Achef_288da1c090ff45c987346d2829257256
    % &indent=off
    % &q=content%3Aattr1__%3D__v%2A

make_solr_query_url(#chef_solr_query{
                       query_string = Query,
                       %% ensure we filter on an org ID
                       filter_query = FilterQuery = "+X_CHEF_database_CHEF_X:chef_" ++ _Rest,
                       start = Start,
                       rows = Rows,
                       sort = Sort}) ->
    Url = "/select?"
        "fq=~s"
        "&indent=off"
        "&q=~s"
        "&start=~B"
        "&rows=~B"
        "&wt=json"
        "&sort=~s",
    io_lib:format(Url, [ibrowse_lib:url_encode(FilterQuery),
                        ibrowse_lib:url_encode(Query),
                        Start, Rows,
                        ibrowse_lib:url_encode(Sort)]).

make_fq_type(ObjType) when ObjType =:= "node";
                           ObjType =:= "role";
                           ObjType =:= "client";
                           ObjType =:= "environment" ->
    "+X_CHEF_type_CHEF_X:" ++ ObjType;
make_fq_type(ObjType) ->
    "+X_CHEF_type_CHEF_X:data_bag_item +data_bag:" ++ ObjType.

index_type("node") ->
    'node';
index_type("role") ->
    'role';
index_type("client") ->
    'client';
index_type("environment") ->
    'environment';
index_type(DataBag) ->
    {'data_bag', DataBag}.
