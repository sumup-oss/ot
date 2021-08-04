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

if Code.ensure_loaded?(Plug) do
  defmodule Ot.Plug do
    alias Ot.Util
    import Plug.Conn

    use Agent

    #
    # An agent is used to hold the runtime config
    # (plug is initialized at build-time)
    # The alternative would be to build the path patterns
    # at each invocation (in call/2), which is very inefficient
    #
    def start_link(config) do
      patterns =
        Keyword.get(config, :paths, ["*"])
        |> Enum.map(&path_to_pattern/1)

      private_tags =
        Keyword.get(config, :conn_private_tags, [])
        |> Enum.reject(fn {_, v} -> is_nil(v) end)

      state = %{
        patterns: patterns,
        private_tags: private_tags,
        response_body_tag: config[:response_body_tag],
        span_name: "request"
      }

      Agent.start_link(fn -> state end, name: __MODULE__)
    end

    def init(_), do: []

    def call(conn, _) do
      config = get_state()

      if Enum.any?(config.patterns, &Regex.match?(&1, conn.request_path)),
        do: process(conn, config),
        else: conn
    end

    #
    # private
    #

    def get_state(), do: Agent.get(__MODULE__, & &1)

    #
    # Convert path patterns to regex patterns:
    # * subpaths:
    #   /v0.1/users/:id => /v0.1/users/[0-9A-Za-z._~-]+
    # - wildcards:
    #   /v0.1/users/*/address => /v0.1/users/.*/address
    #
    def path_to_pattern(path) do
      subp = "[0-9A-Za-z._~-]+"

      pattern =
        ~r{(?<=/):#{subp}(?=/|$)}
        |> Regex.replace(path, "__SUBP__")
        |> String.replace("*", "__WILDCARD__")
        |> Regex.escape()
        |> String.replace("__SUBP__", subp)
        |> String.replace("__WILDCARD__", ".*")

      Regex.compile!("^#{pattern}$")
    end

    def process(conn, config) do
      parent_span =
        conn
        |> get_req_header("traceparent")
        |> List.first()
        |> Ot.parse_traceparent()

      Ot.start_span(config.span_name, parent_span)
      Ot.kind("SERVER")
      Ot.tag("http.path", conn.request_path)
      Ot.tag("http.method", conn.method)
      Ot.tag("http.query_string", Util.truncate(conn.query_string))

      for {key, tag} <- config.private_tags do
        Ot.tag(tag, Util.truncate(conn.private[key]))
      end

      register_before_send(conn, fn conn ->
        Ot.tag("http.status_code", conn.status)

        if config.response_body_tag do
          body = conn.resp_body |> to_string() |> Util.truncate()
          Ot.tag(config.response_body_tag, body)
        end

        conn
      end)
    end
  end
end
