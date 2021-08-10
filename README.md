# Ot

[![License](https://img.shields.io/github/license/sumup-oss/ot)](./LICENSE)

Opentracing for elixir applications.

<!-- MarkdownTOC -->

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick start](#quick-start)
    - [Example usage in a Phoenix app](#example-usage-in-a-phoenix-app)
  - [Configuration](#configuration)
- [Plug](#plug)
- [Module overview and functions](#module-overview-and-functions)
- [Contributing](#contributing)
- [Code of conduct \(CoC\)](#code-of-conduct-coc)
- [About SumUp](#about-sumup)

<!-- /MarkdownTOC -->

<a id="prerequisites"></a>
## Prerequisites

1. You will need a general understanding of opentracing's concepts. You can find a good starting point [here](https://opentracing.io/docs/overview/)
1. [Install](https://elixir-lang.org/install.html) Elixir v1.9 or higher
1. This project depends on [tesla](https://github.com/teamon/tesla). Check out their [documentation](https://github.com/teamon/tesla) to learn more about Tesla and how middlewares work there.
1. Throughout the examples of this readme we have used excerpts of a sample [Phoenix](https://phoenixframework.org/) web app, it is a good idea to get familiar with it first.

<a id="installation"></a>
## Installation

Add this line to your `mix.exs`:

```elixir
defp deps do
  [{:ot, git: "git@github.com:sumup-oss/ot.git", tag: "v1.0.0"}]
end
```

Then run `mix deps.get` and you are good to go!

<a id="quick-start"></a>
## Quick start

```elixir
# See "Configuration" section
Ot.start_link(config)

# See "Module overview and functions" section
Ot.start_span("my-test-span", nil)  # <- span is initialized
Ot.tag("my-tag", "tag-value")       #
Ot.log("log message")               #
Ot.end_span()                       # <- span will be sent to jaeger
```

<a id="example-usage-in-a-phoenix-app"></a>
#### Example usage in a Phoenix app

In `config/dev.exs`:

```elixir
# See "Configuration" section
config :my_app, :ot_config,
  service_name: "my-app",
  collectors: [
    jaeger: [
      url: "http://127.0.0.1:9411/api/v2/spans",
      adapter: Tesla.Adapter.Hackney,
      stringify_tags: true
    ]
  ]
```

In `application.ex`:

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      {Ot, Application.fetch_env!(:my_app, :ot_config)}
      # ... other children
```

In `endpoint.ex`:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # See "Plug" section
  plug Ot.Plug

  # ... other plugs
```

<a id="configuration"></a>
### Configuration

Example with all supported configuration options:

```elixir
# Tesla adapter to use in collectors (can be different for each collector)
# If you use this one, you must add :hackney to your deps
adapter = {Tesla.Adapter.Hackney, connect_timeout: 5000, recv_timeout: 5000}

ot_config = [
  service_name: "my-app",       # (required)
  ignored_exceptions: [         # (optional) don't set "error=true" for these
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
      url: "...",               # (required) span endpoint (Zipkin JSON v2 format)
      adapter: tesla_adapter,   # (required) tesla adapter to use
      flush_interval: 500,      # (optional) buffer flush interval in ms; default: 1000
      flush_retries: 1,         # (optional) flush retry attempts; default: 5 *
      stringify_tags: true,     # (optional) convert tag values to strings (required for jaeger)
      middlewares: []           # (optional) Tesla middlewares; default: []
    ],
    newrelic: [
      url: "https://trace-api.newrelic.com/trace/v1",
      adapter: tesla_adapter,
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
]
```

\* tracing data is stored in a local buffer and sent to the tracing backends
(jaeger, zipkin, etc.) in a batch, every X ms. On failure, the buffer is
preserved and continues to accumulate spans till the next flush (retry).
If the retry limit is exceeded, the buffer is discarded to prevent memory leaks.

<a id="plug"></a>
## Plug

Web applications can use `Ot.Plug` to automatically have a span created for each incoming request.

Let's take a simple ping-pong web app and try this simple request:

```bash
curl 'http://localhost:4000/v0.1/ping?player=just_me'
```

The controller:

```elixir
def MyAppWeb.MyController do
  def ping(conn, params) do
    Ot.tag("opponent", params["player"])
    send_resp(conn, 200, "pong")
  end
end
```

will produce this span, sent to the collector(s):

```json
{
  "annotations": [],
  "duration": 1375,
  "id": "d98f95a2d087a665",
  "kind": "SERVER",
  "localEndpoint":
  {
    "ipv4": "127.0.0.1",
    "port": 0,
    "serviceName": "my-app"
  },
  "name": "request",
  "parentId": null,
  "tags":
  {
    "component": "my-app",
    "author": "just_me",
    "http.method": "GET",
    "http.path": "/v0.1/ping",
    "http.query_string": "player=just_me",
    "http.status_code": "200"
  },
  "timestamp": 1628150108323753,
  "traceId": "0a922fbb7df193916b283610bcc516ff"
}
```

Note that the values of `ipv4` and `port` are hard-coded (could be made configurable in a later release).

<a id="module-overview-and-functions"></a>
## Module overview and functions

Check out the [Module overview](./doc/module_overview.md) docs.

<a id="contributing"></a>
## Contributing

Check out [CONTRIBUTING.md](./CONTRIBUTING.md)

<a id="code-of-conduct-coc"></a>
## Code of conduct (CoC)

We want to foster an inclusive and friendly community around our Open Source efforts. Like all SumUp Open Source projects, this project follows the Contributor Covenant Code of Conduct. Please, [read it and follow it](CODE_OF_CONDUCT.md).

If you feel another member of the community violated our CoC or you are experiencing problems participating in our community because of another individual's behavior, please get in touch with our maintainers. We will enforce the CoC.

<a id="about-sumup"></a>
## About SumUp

![SumUp logo](https://raw.githubusercontent.com/sumup-oss/assets/master/sumup-logo.svg?sanitize=true)

It is our mission to make easy and fast card payments a reality across the *entire* world. You can pay with SumUp in more than 30 countries, already. Our engineers work in Berlin, Cologne, Sofia and Sāo Paulo. They write code in JavaScript, Swift, Ruby, Go, Java, Erlang, Elixir and more. Want to come work with us? [Head to our careers page](https://sumup.com/careers) to find out more.
