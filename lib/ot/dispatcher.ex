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

defmodule Ot.Dispatcher do
  alias Ot.Error
  alias Ot.Span
  alias Ot.Util

  require Logger

  use GenServer

  #
  # Generic call/handle_call functions for automatically
  # setting the logger metadata (to prevent loss of logger context)
  #
  def call(args) do
    {_, caller_trace} = Process.info(self(), :current_stacktrace)
    caller_trace = Enum.slice(caller_trace, 2..-1)
    logger_md = Logger.metadata()
    GenServer.call(__MODULE__, {caller_trace, logger_md, args}, :infinity)
  end

  @impl true
  def handle_call({caller_trace, logger_md, msg}, from, state) do
    old_md = Logger.metadata()

    try do
      Logger.metadata(logger_md)
      _handle_call(msg, from, state)
    rescue
      e ->
        msg =
          Exception.format(:error, e, __STACKTRACE__) <>
            "Caller stack:\n" <>
            Exception.format_stacktrace(caller_trace)

        Logger.error(msg)
        {:reply, :error, state}
    after
      Logger.metadata(old_md)
    end
  end

  #
  # Client API
  #
  # Executed in the calling process
  #
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def stacks,
    do: call(:stacks)

  def current_span,
    do: call(:current_span)

  def link_to_pid(pid),
    do: call({:link_to_pid, pid})

  def log(tag, message),
    do: log("(#{tag}) #{message}")

  def log(message),
    do: call({:log, message})

  def tag(key, value),
    do: call({:tag, key, value})

  def kind(value),
    do: call({:kind, value})

  def end_span,
    do: call(:end_span)

  def start_span(name) when is_bitstring(name) do
    case call(:current_span) do
      nil ->
        "Parent span must be given when starting the first span in a new process"
        |> add_trace()
        |> Logger.error()

        :error

      :error ->
        :error

      pspan ->
        start_span(name, pspan)
    end
  end

  def start_span(name, pspan) when is_bitstring(name) do
    call({:start_span, name, pspan})
  end

  #
  # Server
  #
  # Executed in the server process
  #
  # State:
  # %{
  #   pid1 => [1343, 44432, 3315],
  #   pid2 => [8756, 78659],
  #   pid3 => pid2,
  #   pid4 => [542, 23563],
  #   # ...
  # }
  # (pid3 is a link to pid2: operations in pid3 update the pid2 stack)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      stacks: %{},
      service_name: Keyword.fetch!(opts, :service_name),
      clients: Keyword.fetch!(opts, :clients),
      ignored_exceptions: Keyword.fetch!(opts, :ignored_exceptions)
    }

    {:ok, state}
  end

  def _handle_call(:stacks, _from, state) do
    {:reply, state.stacks, state}
  end

  def _handle_call(:current_span, {pid, _}, state) do
    span = _current_span(state.stacks, pid)
    {:reply, span, state}
  end

  def _handle_call({:link_to_pid, ppid}, {pid, _}, state) do
    stacks = Map.put(state.stacks, pid, ppid)
    Process.monitor(pid)
    {:reply, :ok, %{state | stacks: stacks}}
  end

  def _handle_call({:start_span, name, parent}, {pid, _}, state) do
    span = Span.quickstart(parent, name, state.service_name, %{component: state.service_name})

    stack =
      case get_stack(state.stacks, pid) do
        nil ->
          Process.monitor(pid)
          []

        stack ->
          stack
      end

    stack = [span | stack]
    stacks = update_stack(state.stacks, pid, stack)
    {:reply, span, %{state | stacks: stacks}}
  end

  def _handle_call(:end_span, {pid, _}, state) do
    stack = get_stack!(state.stacks, pid)
    {span, stack} = List.pop_at(stack, 0)

    span
    |> Span.finish()
    |> dispatch(state.clients)

    stacks = update_stack!(state.stacks, pid, stack)
    {:reply, :ok, %{state | stacks: stacks}}
  end

  def _handle_call({:log, message}, {pid, _}, state) do
    stack =
      state.stacks
      |> get_stack!(pid)
      |> List.update_at(0, &Span.annotate(&1, message))

    stacks = update_stack!(state.stacks, pid, stack)

    {:reply, :ok, %{state | stacks: stacks}}
  end

  def _handle_call({:tag, key, value}, {pid, _}, state) do
    stack =
      state.stacks
      |> get_stack!(pid)
      |> List.update_at(0, &Span.tag(&1, key, value))

    stacks = update_stack!(state.stacks, pid, stack)

    {:reply, :ok, %{state | stacks: stacks}}
  end

  def _handle_call({:kind, value}, {pid, _}, state) do
    stack =
      state.stacks
      |> get_stack!(pid)
      |> List.update_at(0, &Span.kind(&1, value))

    stacks = update_stack!(state.stacks, pid, stack)

    {:reply, :ok, %{state | stacks: stacks}}
  end

  #
  # A catch-all clause is needed since we are handling
  # all calls via the generic handle_call
  #
  def _handle_call(msg, _, _),
    do: raise("no _handle_call/3 clause for: #{inspect(msg)}")

  #
  # spans must be evetually closed, or they will never be sent to jaeger
  # => close them whenever owning process exits
  # => close all whenever the genserver exits
  #
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    {stack, stacks} = Map.pop(state.stacks, pid)
    cleanup_stack(stack, reason, state)
    {:noreply, %{state | stacks: stacks}}
  end

  #
  # https://stackoverflow.com/a/48953625/12925939
  #
  def handle_info({:EXIT, _from, reason}, state) do
    cleanup_stacks(state, reason)
    {:stop, reason, %{}}
  end

  @impl true
  def terminate(reason, state) do
    cleanup_stacks(state, reason)
    %{}
  end

  #
  # private
  #

  #
  # If there is a client flush operation running, the end_span call
  # will block until the flush finishes, which must be avoided
  # => use cast
  #
  def dispatch(span, clients) do
    for client_id <- clients do
      Ot.Client.add(client_id, span)
    end
  end

  def cleanup_stacks(state, reason) do
    for {_pid, stack} <- state.stacks do
      cleanup_stack(stack, reason, state)
    end
  end

  def cleanup_stack(stack, _, _) when is_pid(stack),
    do: nil

  def cleanup_stack(stack, reason, state) do
    for span <- stack do
      span
      |> tag_error(reason, state.ignored_exceptions)
      |> Span.finish()
      |> dispatch(state.clients)
    end
  end

  def tag_error(span, reason, ignored) do
    err =
      case reason do
        :normal -> nil
        {{{err, _}, _}, _} -> err
        {err, _} -> err
        any -> any
      end

    if is_struct(err) and err.__struct__ not in ignored do
      span
      |> Span.tag("error", true)
      |> Span.tag("error.object", Util.truncate(err))
    else
      span
    end
  end

  def _current_span(stacks, pid) do
    stack = get_stack(stacks, pid) || []
    List.first(stack)
  end

  def get_stack(stacks, pid) do
    stack = Map.get(stacks, pid)

    if is_pid(stack),
      do: get_stack(stacks, stack),
      else: stack
  end

  def get_stack!(stacks, pid),
    do: get_stack(stacks, pid) || pid_not_found!(pid, stacks)

  def update_stack(stacks, pid, stack) do
    stacks = Map.put_new(stacks, pid, [])
    update_stack!(stacks, pid, stack)
  end

  def update_stack!(stacks, pid, stack) do
    Map.put(stacks, origin_pid(stacks, pid), stack)
  end

  def origin_pid(stacks, pid) do
    stack = Map.get(stacks, pid) || pid_not_found!(pid, stacks)

    if is_pid(stack),
      do: origin_pid(stacks, stack),
      else: pid
  end

  def add_trace(message) do
    trace =
      self()
      |> Process.info(:current_stacktrace)
      |> elem(1)
      |> Exception.format_stacktrace()

    "#{message}\nStacktrace:\n#{trace}"
  end

  def pid_not_found!(pid, stacks) do
    raise Error,
      message:
        "PID not found: #{inspect(pid)}" <>
          ". Maybe you forgot to call Ot.start_span/2 after spawning the process?" <>
          "\nStacks: #{inspect(stacks)}"
  end
end
