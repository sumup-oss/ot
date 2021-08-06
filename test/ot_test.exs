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

defmodule OtTest do
  use ExUnit.Case

  # Test values too long to repeat in tests
  @trace_id String.duplicate("f", 32)
  @span_id String.duplicate("f", 16)

  setup tags do
    ot_config = Map.get(tags, :ot_config, [])
    ot_defaults = [service_name: "my-app", collectors: []]
    start_supervised!({Ot, Keyword.merge(ot_defaults, ot_config)})

    :ok
  end

  test "build_traceparent/1" do
    span = %Ot.Span{id: @span_id, traceId: @trace_id}
    assert Ot.build_traceparent(span) == "00-#{@trace_id}-#{@span_id}-00"
  end

  test "build_traceparent/0" do
    assert Ot.build_traceparent() == nil
    span = Ot.start_span("test", nil)
    assert Ot.build_traceparent() == "00-#{span.traceId}-#{span.id}-00"
  end

  test "parse_traceparent/1" do
    assert Ot.parse_traceparent(nil) == nil

    assert Ot.parse_traceparent("00-#{@trace_id}-#{@span_id}-00") ==
             %Ot.Span{id: @span_id, traceId: @trace_id}
  end
end
