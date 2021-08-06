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

defmodule Ot.Span do
  alias __MODULE__
  alias Ot.Util

  @derive Jason.Encoder

  defstruct traceId: nil,        # "7c7b1272edfd9ae6", renewed when starting a root span
            parentId: nil,       # "0588fe3bb9c9e9a7" | nil
            name: nil,           # "baba"
            id: nil,             # "76d37893af55691d",
            kind: nil,           # "SERVER" | "CLIENT". Unsupported by newrelic: "CONSUMER" | "PRODUCER"
            timestamp: nil,      # 1608126123744875
            duration: nil,       # 521
            localEndpoint: nil,  #
            annotations: nil,    # [%{timestamp: 1608126006342267, value: "log1"}]
            tags: nil            # [{"tag1", "val1"}]

  def start(opts \\ []) do
    %Span{
      traceId: Keyword.get(opts, :traceId, Util.gen_id(16)),
      parentId: Keyword.get(opts, :parentId),
      name: Keyword.get(opts, :name),
      id: Keyword.get(opts, :id, Util.gen_id(8)),
      kind: Keyword.get(opts, :kind),
      timestamp: Keyword.get(opts, :timestamp, Util.timestamp()),
      duration: Keyword.get(opts, :duration),
      localEndpoint:
        Keyword.get(opts, :localEndpoint, %{
          serviceName: Keyword.get(opts, :serviceName),
          ipv4: "127.0.0.1",
          port: 0
        }),
      annotations: Keyword.get(opts, :annotations, []),
      tags: Keyword.get(opts, :tags, %{})
    }
  end

  #
  # Different API for starting a span:
  # Used internally by Ot.Dispatcher for better performance
  # (no keyword list of options)
  #

  def quickstart(nil, name, sname, tags),
    do: quickstart(Util.gen_id(16), nil, name, sname, tags)

  def quickstart(%Span{traceId: tid, id: pid}, name, sname, tags),
    do: quickstart(tid, pid, name, sname, tags)

  def quickstart(tid, pid, name, sname, tags) do
    %Span{
      traceId: tid,
      parentId: pid,
      name: name,
      id: Util.gen_id(8),
      kind: nil,
      timestamp: Util.timestamp(),
      duration: nil,
      localEndpoint: %{serviceName: sname, ipv4: "127.0.0.1", port: 0},
      annotations: [],
      tags: tags
    }
  end

  def kind(span, nil),
    do: span

  def kind(span, value) when value in ["SERVER", "CLIENT", "PRODUCER", "CONSUMER"],
    do: %{span | kind: value}

  def annotate(span, nil), do: span

  def annotate(span, msg),
    do: %{span | annotations: [%{timestamp: Util.timestamp(), value: msg} | span.annotations]}

  def tag(span, nil, _), do: span

  def tag(span, key, value) when is_bitstring(key),
    do: %{span | tags: Map.put(span.tags, key, value)}

  def finish(%{duration: nil} = span) do
    %{
      span
      | duration: Util.timestamp() - span.timestamp,
        annotations: Enum.reverse(span.annotations)
    }
  end
end
