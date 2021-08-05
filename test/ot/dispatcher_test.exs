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

defmodule Ot.DispatcherTest do
  alias Ot.{Dispatcher, Span}
  use ExUnit.Case

  #
  # A simple mock for dispatcher clients
  # It accumulates whatever spans via are given Client.add/2
  #
  defmodule MockClient do
    use GenServer

    def start_link(_),
      do: GenServer.start_link(__MODULE__, [], name: :mock_client)

    def init(_), do: {:ok, []}

    # Mock for Clent.add/2
    def handle_cast({:add, span}, spans),
      do: {:noreply, [span | spans]}

    # Helper function used in this test only
    def added_spans(),
      do: :sys.get_state(:mock_client)
  end

  #
  # A simple mock to emulate operating with spans in a separate process
  # It calls function is given via proxy/1
  #
  defmodule MockProcess do
    use Agent

    def start_link(_),
      do: Agent.start_link(fn -> [] end)

    def proxy(pid, fun),
      do: Agent.get(pid, fn _ -> fun.() end)
  end

  setup tags do
    config = Map.get(tags, :config, [])
    defaults = [service_name: "my-app", clients: [:mock_client], ignored_exceptions: []]
    start_supervised!({Dispatcher, Keyword.merge(defaults, config)})

    :ok
  end

  test "start_span/2" do
    # Start a span (orphan)
    pspan = Dispatcher.start_span("my-span", nil)
    assert %Span{} = pspan
    assert pspan.parentId == nil
    assert <<_::binary-size(32)>> = pspan.traceId
    assert <<_::binary-size(16)>> = pspan.id
    assert pspan.name == "my-span"
    assert pspan.localEndpoint.serviceName == "my-app"

    # Start a span (child)
    span = Dispatcher.start_span("my-span", pspan)
    assert %Span{} = span
    assert span.traceId == pspan.traceId
    assert span.parentId == pspan.id
  end

  test "start_span/1" do
    # No current span
    assert :error = Dispatcher.start_span("my-span")

    # With current span
    pspan = Dispatcher.start_span("parent-span", nil)
    span = Dispatcher.start_span("my-span")
    assert span.traceId == pspan.traceId
    assert span.parentId == pspan.id
  end

  test "current_span/0" do
    assert Dispatcher.current_span() == nil
    span = Dispatcher.start_span("my-span", nil)
    assert ^span = Dispatcher.current_span()
  end

  test "link_to_pid/1" do
    span = Dispatcher.start_span("my-span-1", nil)

    # Simulate another running process, linked
    mpid = self()
    lpid = start_supervised!(MockProcess, id: :lpid)
    MockProcess.proxy(lpid, fn -> Ot.link_to_pid(mpid) end)

    # Linked pid sees the current span of the main pid
    assert ^span = MockProcess.proxy(lpid, fn -> Ot.current_span() end)
  end

  test "stacks/0" do
    # Initially, stack is empty
    assert Dispatcher.stacks() == %{}

    # Simulate 3 running processes (1 main, 1 orphan, 1 linked)
    mpid = self()
    opid = start_supervised!(MockProcess, id: :opid)
    lpid = start_supervised!(MockProcess, id: :lpid)
    MockProcess.proxy(lpid, fn -> Ot.link_to_pid(mpid) end)

    # Open some spans
    span1 = Dispatcher.start_span("my-span-1", nil)
    span2 = Dispatcher.start_span("my-span-2")
    :error = MockProcess.proxy(opid, fn -> Dispatcher.start_span("my-span-3") end)
    span4 = MockProcess.proxy(lpid, fn -> Dispatcher.start_span("my-span-4") end)

    # opid failed to create a span
    assert Dispatcher.stacks() == %{
      mpid => [span4, span2, span1],  # mpid also contains mpid's spans
      lpid => mpid                    # lpid is linked to mpid
    }
  end

  test "log/1" do
    # No current span => :error
    assert :error = Dispatcher.log("baba")

    Dispatcher.start_span("my-span", nil)
    assert :ok = Dispatcher.log("baba")
    assert [%{timestamp: t, value: "baba"}] = Dispatcher.current_span().annotations
    assert is_integer(t)
  end

  test "log/2" do
    Dispatcher.start_span("my-span", nil)
    assert :ok = Dispatcher.log("baba", "pena")
    assert [%{timestamp: _, value: "(baba) pena"}] = Dispatcher.current_span().annotations
  end

  test "tag/2" do
    # No current span => :error
    assert :error = Dispatcher.tag("baba", "pena")

    Dispatcher.start_span("my-span", nil)
    assert :ok = Dispatcher.tag("baba", "pena")
    assert %{"baba" => "pena"} = Dispatcher.current_span().tags
  end

  test "kind/1" do
    # No current span => :error
    assert :error = Dispatcher.kind("CLIENT")

    Dispatcher.start_span("my-span", nil)

    # Invalid value
    assert :error = Dispatcher.kind("BABA")
    assert :ok = Dispatcher.kind("CLIENT")
  end

  test "end_span/0" do
    # No current span => :error
    assert :error = Dispatcher.end_span()

    span = Dispatcher.start_span("my-span", nil)

    start_supervised!({MockClient, []})
    assert :ok = Dispatcher.end_span()
    assert [added_span] = MockClient.added_spans()

    # Ending the span also sets its duration
    refute added_span.duration == nil
    assert %{added_span | duration: nil} == span
  end

  # TODO
  # I can't figure out how to test a crash in the supervised process
  # because it always crashes the main test process too
  #
  # test "error handling" do
  #   # Simulate another running process, linked
  #   pid = start_supervised!(MockProcess, id: :lpid, restart: :temporary)
  #   assert span = MockProcess.proxy(pid, fn -> Ot.start_span("my-span", nil) end)
  #
  #   # This "raise" brings down the main test process - why?
  #   MockProcess.proxy(pid, fn -> raise "error" end)
  # end

  # test "cleanup_stack/3: ignored exception" do

end
