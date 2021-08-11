# Module overview

[![License](https://img.shields.io/github/license/sumup-oss/ot)](./LICENSE)

<!-- MarkdownTOC -->

- [`Ot` functions](#ot-functions)
  - [`stacks/0`](#stacks0)
  - [`start_span/1`](#start_span1)
  - [`start_span/2`](#start_span2)
  - [`current_span/0`](#current_span0)
  - [`end_span/0`](#end_span0)
  - [`log/1`](#log1)
  - [`tag/2`](#tag2)
  - [`link_to_pid/1`](#link_to_pid1)

<!-- /MarkdownTOC -->

The modules used here are:

* `Ot` - main module and supervisor; delegates most function calls to `Ot.Dispatcher`
* `Ot.Span` - a [span](https://opentracing.io/docs/overview/spans/) represented by a struct
* `Ot.Dispatcher` - an in-memory storage for open spans. Closed spans are sent to collector clients
* `Ot.Client` - an HTTP client for span collectors (eg. jaeger). Sends buffered spans to the collector every X msec
* `Ot.Plug` - a [plug](https://hexdocs.pm/phoenix/1.5.6/plug.html) for your app to trace incoming HTTP requests
* `Ot.TeslaMiddleware.Traceparent` - a [tesla middleware](https://hexdocs.pm/tesla/1.4.0/Tesla.Middleware.html) for your app's Tesla HTTP clients to trace external HTTP calls

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
