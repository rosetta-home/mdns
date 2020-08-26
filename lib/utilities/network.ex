defmodule Mdns.Utilities.Network do
  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  @spec reuse_port :: [{:raw, 65535, 512 | 4, <<_::32>>}]
  def reuse_port do
    case :os.type() do
      {:unix, :linux} ->
        reuse_port_linux()

      {:unix, os_name} when os_name in [:darwin, :freebsd, :openbsd, :netbsd] ->
        get_reuse_port()

      {:win32, _unused} ->
        get_reuse_address()

      _ ->
        []
    end
  end

  def mdns_port, do: Application.get_env(:mdns, :port, 5353)

  def mdns_group, do: {224, 0, 0, 251}

  defp reuse_port_linux() do
    case :os.version() do
      {major, minor, _} when major > 3 or (major == 3 and minor >= 9) ->
        get_reuse_port()

      _before_3_9 ->
        get_reuse_address()
    end
  end

  defp get_reuse_port(), do: [{:raw, @sol_socket, @so_reuseport, <<1::native-32>>}]

  defp get_reuse_address(), do: [{:raw, @sol_socket, @so_reuseaddr, <<1::native-32>>}]
end
