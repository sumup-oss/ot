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

defmodule Ot.SpanTest do
  alias Ot.Span
  use ExUnit.Case

  test "start/1" do
    span_opts = [
      parentId: "test-parent",
      name: "test-name",
      kind: "SERVER",
      serviceName: "test-service"
    ]

    before_timestamp = System.os_time(:microsecond)
    span = Span.start(span_opts)
    after_timestamp = System.os_time(:microsecond)

    assert span.parentId == "test-parent"
    assert span.name == "test-name"
    assert span.kind == "SERVER"
    assert span.duration == nil

    # auto-generated fields
    assert <<_::binary-size(16)>> = span.id
    assert <<_::binary-size(32)>> = span.traceId
    assert span.timestamp >= before_timestamp
    assert span.timestamp <= after_timestamp

    assert span.localEndpoint == %{
             serviceName: "test-service",
             ipv4: "127.0.0.1",
             port: 0
           }
  end

  test "quickstart/4" do
    span = Span.quickstart(nil, "a", "b", %{"c" => "d"})

    assert <<_::binary-size(16)>> = span.id
    assert <<_::binary-size(32)>> = span.traceId
    assert span.parentId == nil
    assert span.name == "a"
    assert span.localEndpoint.serviceName == "b"
    assert span.tags == %{"c" => "d"}
  end

  test "quickstart/5" do
    span = Span.quickstart("a", "b", "c", "d", %{"e" => "f"})

    assert <<_::binary-size(16)>> = span.id
    assert span.traceId == "a"
    assert span.parentId == "b"
    assert span.name == "c"
    assert span.localEndpoint.serviceName == "d"
    assert span.tags == %{"e" => "f"}
  end

  test "annotate/2" do
    before_timestamp = System.os_time(:microsecond)
    span = Span.start() |> Span.annotate("test annotation")
    after_timestamp = System.os_time(:microsecond)

    assert [%{timestamp: timestamp, value: "test annotation"}] = span.annotations
    assert timestamp >= before_timestamp
    assert timestamp <= after_timestamp
  end

  test "tag/3" do
    span = Span.start() |> Span.tag("test-tag", "test value")
    assert %{"test-tag" => "test value"} = span.tags
  end

  test "finish/1" do
    before_timestamp = System.os_time(:microsecond)
    span = Span.start() |> Span.finish()
    after_timestamp = System.os_time(:microsecond)

    assert span.duration <= after_timestamp - before_timestamp
  end
end
