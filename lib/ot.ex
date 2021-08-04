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

defmodule Ot do
  alias Ot.Span
  alias Ot.Dispatcher

  use Supervisor

  defmodule Error do
    defexception [:message]
  end

  defdelegate stacks, to: Dispatcher
  defdelegate current_span, to: Dispatcher
  defdelegate link_to_pid(pid), to: Dispatcher
  defdelegate start_span(name), to: Dispatcher
  defdelegate start_span(name, pspan), to: Dispatcher
  defdelegate end_span, to: Dispatcher
  defdelegate log(tag, message), to: Dispatcher
  defdelegate log(message), to: Dispatcher
  defdelegate tag(key, value), to: Dispatcher
  defdelegate kind(value), to: Dispatcher

  #
  # https://www.w3.org/TR/trace-context/#examples-of-http-traceparent-headers
  # https://github.com/opentracing/specification/blob/master/rfc/trace_identifiers.md#trace-context-http-headers
  #
  def build_traceparent, do: Dispatcher.current_span() |> build_traceparent()
  def build_traceparent(nil), do: nil
  def build_traceparent(span), do: "00-#{span.traceId}-#{span.id}-00"

  def parse_traceparent(
        "00-" <> <<trace_id::binary-size(32)>> <> "-" <> <<span_id::binary-size(16)>> <> "-00"
      ),
      do: %Span{traceId: trace_id, id: span_id}

  def parse_traceparent(_), do: nil

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  # On shutdown, first terminate Dispatcher, then the Client
  # (to ensure all spans are finalized *and then* flushed)
  def init(_) do
    clients = client_specs()
    children = clients ++ [dispatcher_spec(clients)] ++ plug_specs()
    Supervisor.init(children, strategy: :one_for_one)
  end

  #
  # private
  #

  def client_specs do
    for {cname, copts} <- Application.fetch_env!(:ot, :collectors) do
      copts = Keyword.put(copts, :id, :"ot.client.#{cname}")
      Supervisor.child_spec({Ot.Client, copts}, id: copts[:id])
    end
  end

  def dispatcher_spec(clients) do
    {Ot.Dispatcher,
     service_name: Application.fetch_env!(:ot, :service_name),
     clients: Enum.map(clients, & &1.id),
     ignored_exceptions: Application.get_env(:ot, :ignored_exceptions, [])}
  end

  if Code.ensure_loaded?(Plug) do
    def plug_specs(), do: [{Ot.Plug, Application.get_env(:ot, :plug, [])}]
  else
    def plug_specs(), do: []
  end
end
