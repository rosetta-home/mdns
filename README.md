# Mdns

A simple [mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) client for device discovery on your local network.

## Installation

    1. git clone https://github.com/NationalAssociationOfRealtors/mdns.git
    2. mix do deps.get, deps.compile
    3. iex -S mix

## Usage
On startup `Mdns.Client` will broadcast a discovery packet over the local network. Compliant devices will respond with a DNS response. `Mdns.Client` will notify the event bus, available at `Mdns.Client.Events`, of any devices it finds. Every 10 seconds it sends out another discovery broadcast to find any new devices on the network. The event bus will broadcast all devices, not just the new ones it finds. It is up to the developer to handle de-duping the devices broadcast over the event bus. However there is a function `Mdns.Client.devices` that will return a list of all the unique devices on the network.

The events broadcast over the event bus are in the form `{:device, device}` where the device is a Map that consists of the following fields.

    %Mdns.Client.Device{
        answers: [
            %{
                class: :in,
                data: '_googlecast._tcp.local',
                domain: '_services._dns-sd._udp.local',
                ttl: 4500,
                type: :ptr
            }
        ],
        ip: {192, 168, 1, 138}
    }

For an example implementation of an event handler see `Mdns.Handler`. To add a handler to the event bus call `Mdns.Client.add_handler(handler)`

    defmodule Mdns.Handler do
        use GenEvent
        require Logger

        def init do
            {:ok, []}
        end

        def handle_event({:device, device} = obj, parent) do
            send(parent, obj)
            {:ok, parent}
        end
    end
