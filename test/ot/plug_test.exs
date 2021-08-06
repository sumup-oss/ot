#
# Copyright 2021, SumUp Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

defmodule Ot.PlugTest do
  use ExUnit.Case
  use Plug.Test

  @trace_id String.duplicate("a", 32)
  @span_id String.duplicate("b", 16)
  @traceparent "00-#{@trace_id}-#{@span_id}-00"

  setup tags do
    # Start Ot
    ot_config = Map.get(tags, :ot_config, [])
    ot_defaults = [service_name: "my-app", collectors: []]
    start_supervised!({Ot, Keyword.merge(ot_defaults, ot_config)})

    :ok
  end

  @tag ot_config: [plug: [paths: ["/foo/*"]]]
  test "call/2: ignored path" do
    conn(:get, "/bar") |> Ot.Plug.call([])
    assert Ot.current_span() == nil
  end

  @tag ot_config: [plug: [paths: ["/foo/*"]]]
  test "call/2: matched path" do
    conn = conn(:get, "/foo/bar?baz=0") |> Ot.Plug.call([])
    span = Ot.current_span()

    assert %Ot.Span{} = span
    assert <<_::binary-size(16)>> = span.id
    assert <<_::binary-size(32)>> = span.traceId
    assert span.name == "request"
    assert span.parentId == nil
    assert span.kind == "SERVER"

    assert span.tags == %{
             :component => "my-app",
             "http.method" => "GET",
             "http.path" => "/foo/bar",
             "http.query_string" => "baz=0"
           }

    send_resp(conn, 200, "OK")
    assert Ot.current_span().tags == Map.put(span.tags, "http.status_code", 200)
  end

  test "call/2: traceparent" do
    conn(:get, "/foo/bar?baz=0")
    |> put_req_header("traceparent", @traceparent)
    |> Ot.Plug.call([])

    span = Ot.current_span()

    assert <<_::binary-size(16)>> = span.id
    refute span.id == @span_id
    assert span.traceId == @trace_id
  end

  test "call/2: query string tuncation" do
    onek = String.duplicate("a", 1000)
    conn(:get, "/foo/bar?" <> onek <> "a") |> Ot.Plug.call([])

    assert Ot.current_span().tags["http.query_string"] == onek
  end

  @tag ot_config: [plug: [conn_private_tags: [test_private_tag: "test_span_tag"]]]
  test "call/2: private field tagging" do
    conn(:get, "/foo/bar")
    |> put_private(:test_private_tag, "test-value")
    |> Ot.Plug.call([])

    assert Ot.current_span().tags["test_span_tag"] == "test-value"
  end
end
