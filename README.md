# Ot

[![License](https://img.shields.io/github/license/sumup-oss/ot)](./LICENSE)

Opentracing for elixir applications.

<!-- MarkdownTOC -->

- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
  - [Configuration](#configuration)
- [Module overview](#module-overview)
- [`Ot` functions](#ot-functions)
    - [`stacks/0`](#stacks0)
    - [`start_span/1`](#start_span1)
    - [`start_span/2`](#start_span2)
    - [`current_span/0`](#current_span0)
    - [`end_span/0`](#end_span0)
    - [`log/1`](#log1)
    - [`tag/2`](#tag2)
    - [`link_to_pid/1`](#link_to_pid1)
  - [Contributing](#contributing)

<!-- /MarkdownTOC -->

<a id="prerequisites"></a>
## Prerequisites

1. You know what [opentracing](https://opentracing.io/docs/overview/) is -- `ot` is a client library for it
1. [install](https://elixir-lang.org/install.html) Elixir v1.9 or higher
1. This project depends on [tesla](https://github.com/teamon/tesla). To use `ot`, you should know about Tesla plugs.
1. Usage examples for `ot` assume a [Phoenix](https://phoenixframework.org/) web app, you should know how a basic Phoenix app works.

<a id="quick-start"></a>
## Quick start

Example usage for Phoenix app

In `mix.exs`:

```elixir
defp deps do
  #
  # use the latest tag in https://github.com/sumup-oss/ot/tags
  #
  [{:ot, git: "git@github.com:sumup-oss/ot.git", tag: "v1.0.0"}]
end
```

In `config/dev.exs`:

```elixir
config :ot,
  service_name: "my-app",
  collectors: [
    jaeger: [
      url: "http://127.0.0.1:9411/api/v2/spans",
      stringify_tags: true
    ]
  ]
```

In `application.ex`:

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      Ot,
      # ...
```

In `endpoint.ex`:

```elixir
defmodule MyAppWeb.Endpoint do
  plug Ot.Plug, paths: ["/v0.1/*"]
end
```

<a id="configuration"></a>
### Configuration

```elixir
config :ot,
  service_name: "my-app",    # (required)
  ignored_exceptions: [      # (optional) don't set "error=true" for these
    Phoenix.Router.NoRouteError
  ],
  plug: [                                      # (optional) config for Ot.Plug
    paths: ["/v0.1/*"],                        # (optional) paths to work with; default: ["*"]
    response_body_tag: "http.response_body",   # (optional) tag resp body as "http.resp_body"; default: nil (no tag)
    conn_private_tags: [                       # (optional) list of conn-private fields to tag; default: []
      req_body: "http.request_body",           #    tag conn.private.req_body as "http.request_body"
      req_id: "http.request_id"                #    tag conn.private.req_id as "http.request_id"
    ]
  ],
  collectors: [
    jaeger: [
      url: "...",            # (required) span endpoint (Zipkin JSON v2 format)
      flush_interval: 500,   # (optional) buffer flush interval in ms; default: 1000
      flush_retries: 1,      # (optional) flush retry attempts; default: 5 *
      stringify_tags: true,  # (optional) convert tag values to strings (required for jaeger)
      middlewares: []        # (optional) Tesla middlewares; default: []
    ],
    newrelic: [
      url: "https://trace-api.newrelic.com/trace/v1",
      middlewares: [
        Tesla.Middleware.Logger,
        {Tesla.Middleware.Headers, [
          {"api-key", "..."},
          {"data-format", "zipkin"},
          {"data-format-version", "2"}
        ]}
      ]
    ]
  ]
```

\* tracing data is stored in a local buffer and sent to the tracing backends (jaeger, zipkin, etc.) in a batch, every X ms. On failure, the buffer is preserved and continues to accumulate spans till the next flush (retry). If the retry limit is exceeded, the buffer is discarded to prevent memory leaks.

<a id="module-overview"></a>
## Module overview

* `Ot` - main module and supervisor; delegates most function calls to `Ot.Dispatcher`
* `Ot.Span` - a [span](https://opentracing.io/docs/overview/spans/) represented by a struct
* `Ot.Dispatcher` - an in-memory storage for open spans. Closed spans are sent to collector clients
* `Ot.Client` - an HTTP client for span collectors (eg. jaeger). Sends buffered spans to the collector every X msec
* `Ot.Plug` - a [plug](https://hexdocs.pm/phoenix/1.5.6/plug.html) for your app to trace incoming HTTP requests
* `Ot.TeslaMiddleware` - a [tesla middleware](https://hexdocs.pm/tesla/1.4.0/Tesla.Middleware.html) for your app's Tesla HTTP clients to trace external HTTP calls

<a id="ot-functions"></a>
## `Ot` functions

The main module `Ot` supervises the `Ot.Dispatcher` (GenServer) and `Ot.Client` (GenServer, one for each collector)

It delegates function calls to a `GenServer` which keeps state in a map of `<pid> => [<span>, <span>, ...]`.

All spans created by an Erlang process are implicitly closed when that process exits (see [`link_to_pid/1`](#link_to_pid1))

<a id="stacks0"></a>
#### `stacks/0`
Returns the current state (map of `<pid>` => `[span, ...])`.

<a id="start_span1"></a>
#### `start_span/1`
Start a new span with the given name. The span is a child of the current process's active span.

<a id="start_span2"></a>
#### `start_span/2`
Same as `start_span/1`, but with explicit parent.

When there is no parent (ie. this is the trace entrypoint), an explicit `nil` is required as the parent:

```elixir
# A span without a parent (starts a new trace):
Ot.start_span("span-a", nil)
Ot.log("log msg#1")
parent_span = Ot.current_span()

Task.async(fn ->
  # A span with a parent (adds it to the same trace):
  Ot.start_span("span-b", parent_span)
  Ot.log("log msg#2")
)

Ot.log("log msg#3")
```

In the example above, `span-b` is the child of `span-a`

`log msg#1` and `log msg#3` are linked to `span-a`, and `log msg#2` - to `span-b`


<a id="current_span0"></a>
#### `current_span/0`
Returns the currently active span for the current process. Calls to `log/1` and `tag/2` will default to it, as will `start_span/1`.

<a id="end_span0"></a>
#### `end_span/0`
End the currently active span in the process.

This call is optional, because when a process exits, all its opened spans are automatically closed.

Eg. for a typical Phoenix application, incoming requests are served by individual Cowboy processes which die shortly after the response is sent.


<a id="log1"></a>
#### `log/1`
Attach the given string as log message to the currently active span.

```elixir
Ot.log("free text")
```

<a id="tag2"></a>
#### `tag/2`
Tag the currently active span with the given `key` and `value`.

```elixir
Ot.tag("transaction-id", "d4bfb871-e42d-42ff-bd6c-8aa6f69f3d91")
```

<a id="link_to_pid1"></a>
#### `link_to_pid/1`
Manually links spans to processes.

By default, each erlang process requires a separate span. If you don't want that, use this function:

```elixir
Ot.log("log msg#1")
parent_pid = self()

Task.async(fn ->
  # Use the span of another process
  Ot.link_to_pid(parent_pid)
  Ot.log("log msg#2")
)

Ot.log("log msg#3")
```

In the example above, all 3 log messages will be linked to the same span.

***NOTE***: when a linked pid is terminated, no spans will be closed (they will be closed when the original pid exits). In the example above, when the async `Task` finishes, the span will remain as long as `parent_pid` is alive.

<a id="contributing"></a>
### Contributing

Contributions are welcome! This project still supports only a small subset of the features a full-blown opentracing client needs, but with your help it can become better :)

If you spot an issue with the current functionality, please open an [issue](https://github.com/sumup-oss/ot/issues)

If you'd like some new functionality, feel free to make a contribution to the project:

1. Fork it
1. Write your code, format it using `mix format`
1. Tests are recommended, but not mandatory
1. Submit a pull request
