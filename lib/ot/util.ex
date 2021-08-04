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

defmodule Ot.Util do
  def gen_id(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  def timestamp(unit \\ :microsecond),
    do: System.os_time(unit)

  def truncate(nil), do: ""
  def truncate(msg) when not is_bitstring(msg), do: truncate(inspect(msg))
  def truncate(msg), do: String.slice(msg, 0, 1000)

  def clone_logger_metadata(md) do
    md
    |> Keyword.merge(node_id: Node.self(), process_id: inspect(self()))
    |> Logger.metadata()
  end

  def with_logger_metadata(md, fun) do
    old_md = Logger.metadata()
    clone_logger_metadata(md)
    res = fun.()
    clone_logger_metadata(old_md)
    res
  end
end
