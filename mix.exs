defmodule Mdns.Mixfile do
  use Mix.Project

  def project do
    [app: :mdns,
     version: "0.1.1",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
        applications: [:logger],
        mod: {Mdns, []}
    ]
  end

  def description do
      """
      A simple mDNS (zeroconf, bonjour) client for device discovery on your local network.
      """
  end

  def package do
    [
      name: :mdns,
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Christopher Steven Coté"],
      licenses: ["MIT License"],
      links: %{"GitHub" => "https://github.com/NationalAssociationOfRealtors/mdns",
          "Docs" => "https://github.com/NationalAssociationOfRealtors/mdns"}
    ]
  end

  defp deps do
    [{:dns, "~> 0.0.4"}]
  end
end
