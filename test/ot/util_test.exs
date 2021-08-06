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

defmodule Ot.UtilTest do
  alias Ot.Util
  use ExUnit.Case

  test "gen_id/1" do
    # 8 bytes, base16 encoded (4 bits/char) => 16 chars
    assert <<id1::binary-size(16)>> = Util.gen_id(8)
    assert <<id2::binary-size(16)>> = Util.gen_id(8)
    assert id1 !== id2
  end

  test "truncate/1" do
    assert Util.truncate(nil) == ""

    ok_string = String.duplicate("a", 1000)
    long_string = ok_string <> "a"

    assert Util.truncate(ok_string) == ok_string
    assert Util.truncate(long_string) == ok_string
  end
end
