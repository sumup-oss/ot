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

defmodule Ot.MixProject do
  use Mix.Project

  @version "3.0.0"
  @description "Opentracing support for Elixir applications."

  def project do
    [
      app: :ot,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: @description,
      name: "Ot"
    ]
  end

  defp package() do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Simeon Manolov"],
      name: "ot",
      links: %{"GitHub" => "https://github.com/sumup-oss/ot"},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, ">= 0.0.0", optional: true},
      {:jason, ">= 0.0.0"},
      {:tesla, ">= 0.0.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
