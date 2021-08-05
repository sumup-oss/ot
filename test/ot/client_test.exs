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

defmodule Ot.ClientTest do
  use ExUnit.Case

  alias Ot.Client
  import ExUnit.CaptureLog


  setup tags do
    config = Map.get(tags, :config, [])
    defaults = [
      id: :mock,
      url: "http://localhost",
      adapter: Tesla.Mock,
      flush_interval: :timer.hours(1)
    ]

    pid = start_supervised!({Client, Keyword.merge(defaults, config)})

    {:ok, pid: pid}
  end

  test "add/2", %{pid: pid} do
    assert :ok = Client.add(pid, %Ot.Span{})
  end

  test "flush/1", %{pid: pid} do
    span = %Ot.Span{}
    Client.add(pid, span)
    body = Jason.encode!([span])

    ok_env = %Tesla.Env{status: 200, body: ""}
    Tesla.Mock.mock(fn %{method: :post, body: ^body} -> ok_env end)

    state = :sys.get_state(pid)
    assert :ok = Client.flush(state)

    err_env = %Tesla.Env{status: 400, body: "tesla-error"}
    Tesla.Mock.mock(fn %{method: :post, body: ^body} -> err_env end)

    state = :sys.get_state(pid)

    assert capture_log(fn -> Client.flush(state) end) =~
      "Flush failed: the server replied with status 400. Resp body: tesla-error"

    fatal_env = %Tesla.Env{status: nil}
    Tesla.Mock.mock(fn %{method: :post, body: ^body} -> fatal_env end)

    state = :sys.get_state(pid)
    assert capture_log(fn -> Client.flush(state) end) =~ "Flush failed"
  end
end
