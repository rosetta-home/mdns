defmodule Mdns.Utilities.Network do

  @sol_socket 0xFFFF
  @so_reuseport 0x0200

  def reuse_port do
    case :os.type() do
      {:unix, os_name} ->
        unix_reuse_port(os_name)

      _ ->
        []
    end
  end

  defp unix_reuse_port(os_name) when os_name in [:darwin, :freebsd, :openbsd, :netbsd],
    do: [{:raw, @sol_socket, @so_reuseport, <<1::native-32>>}]

  defp unix_reuse_port(_), do: []
end
