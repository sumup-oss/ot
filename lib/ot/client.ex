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

defmodule Ot.Client do
  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :id))
  end

  #
  # Pass the logger metadata to prevent loss of logger context
  #
  def add(pid, span) do
    GenServer.cast(pid, {:add, span})
  end

  #
  # Options example:
  #
  # [
  #   id: :"ot.client.jaeger",
  #   url: "http://127.0.0.1:9411/api/v2/spans",
  #   flush_interval: 1000,
  #   flush_retries: 1,
  #   stringify_tags: false,
  #   middlewares: [{Tesla.Middleware.Logger}]
  # ]
  #
  @impl true
  def init(opts) do
    middlewares = [{Tesla.Middleware.BaseUrl, Keyword.fetch!(opts, :url)}]
    client =
      Tesla.client(
        middlewares ++ Keyword.get(opts, :middlewares, []),
        Keyword.fetch!(opts, :adapter)
      )

    state = %{
      id: Keyword.fetch!(opts, :id),
      interval: Keyword.get(opts, :flush_interval, 1000),
      retries: Keyword.get(opts, :flush_retries, 5),
      errors: 0,
      stringify_tags: Keyword.get(opts, :stringify_tags, false),
      spans: [],
      client: client
    }

    Logger.metadata(context: to_string(opts[:id]))
    Logger.debug("client starting...")
    Process.send(self(), :flush, [])
    {:ok, state}
  end

  @impl true
  def handle_cast({:add, span}, state) do
    # Logger.debug("add span")
    span =
      if state.stringify_tags,
        do: stringify_tags(span),
        else: span

    {:noreply, %{state | spans: [span | state.spans]}}
  end

  defp stringify_tags(span) do
    tags = for {k, v} <- span.tags, into: %{}, do: {k, to_string(v)}
    %{span | tags: tags}
  end

  #
  # Periodically executed every X seconds
  #
  @impl true
  def handle_info(:flush, %{spans: []} = state) do
    Process.send_after(self(), :flush, state.interval)
    {:noreply, state}
  end

  def handle_info(:flush, state) do
    # Logger.debug("flush")
    state =
      case flush(state) do
        :ok ->
          %{state | spans: [], errors: 0}

        _ ->
          if state.errors >= state.retries do
            Logger.error("Discard #{length(state.spans)} spans after #{state.errors} errors")
            %{state | spans: [], errors: 0}
          else
            %{state | errors: state.errors + 1}
          end
      end

    Process.send_after(self(), :flush, state.interval)
    {:noreply, state}
  end

  #
  # https://stackoverflow.com/a/48953625/12925939
  #
  def handle_info({:EXIT, _from, reason}, state) do
    flush(state)
    {:stop, reason, %{}}
  end

  @impl true
  def terminate(_reason, state) do
    flush(state)
    %{}
  end

  def flush(%{spans: []}),
    do: :ok

  def flush(state) do

    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(state.spans)
    Logger.debug(body)

    case Tesla.post(state.client, "", body, headers: headers) do
      {:ok, %{status: s}} when s >= 200 and s < 300 ->
        Logger.debug("Sent #{length(state.spans)} spans")
        :ok

      {:ok, %{status: s, body: b}} = env when is_integer(s) ->
        Logger.warn("Flush failed: the server replied with status #{s}. Resp body: #{b}")
        {:warn, env}

      other ->
        Logger.warn("Flush failed: #{inspect(other)}")
        {:warn, other}
    end
  end
end
