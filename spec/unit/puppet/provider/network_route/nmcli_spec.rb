require 'spec_helper'
require 'puppet/provider/network_route/nmcli'

describe Puppet::Type.type(:network_route).provider(:nmcli) do
  def profile(routes: '', gateway: '', active: 'yes')
    allow(described_class).to receive(:nmcli_connection_lookup)
      .and_return('NAME' => 'eth1', 'UUID' => '9c92fad9', 'DEVICE' => 'eth1', 'ACTIVE' => active)
    allow(described_class).to receive(:nmcli_connection_show)
      .and_return('connection.id' => 'eth1', 'connection.uuid' => '9c92fad9',
                  'ipv4.routes' => routes, 'ipv4.gateway' => gateway)
    allow(described_class).to receive(:nmcli_device_reapply)
  end

  def route(destination, gateway = '10.121.21.1', metric = nil)
    resource = Puppet::Type.type(:network_route).new(
      {
        name: "#{destination} via #{gateway}",
        ensure: :present,
        destination: destination,
        gateway: gateway,
        device: 'eth1',
        provider: :nmcli,
      }.merge(metric ? { metric: metric } : {}),
    )
    described_class.new(resource)
  end

  # A route is either the connection gateway or an entry of its route list,
  # and the destination decides which.
  describe 'a route that is not the default one' do
    it 'exists when the list carries its destination' do
      profile(routes: '10.121.21.0/24 10.121.21.1, 10.99.0.0/24 10.99.0.1')

      expect(route('10.121.21.0/24')).to exist
    end

    it 'does not exist when the list does not' do
      profile(routes: '10.99.0.0/24 10.99.0.1')

      expect(route('10.121.21.0/24')).not_to exist
    end

    it 'is added as one entry rather than by writing the list' do
      profile

      expect(described_class).to receive(:nmcli_list_add)
        .with('9c92fad9', 'ipv4.routes', '10.121.21.0/24 10.121.21.1')

      route('10.121.21.0/24').create
    end

    # `-ipv4.routes "10.99.91.0/24"` against a stored
    # "10.99.91.0/24 10.99.92.253 200" exits 0 and removes nothing, so the
    # entry goes back exactly as the profile spells it, metric and all.
    it 'is removed by the entry the profile carries, not the one declared' do
      profile(routes: '10.121.21.0/24 10.121.21.1 200')

      expect(described_class).to receive(:nmcli_list_remove)
        .with('9c92fad9', 'ipv4.routes', '10.121.21.0/24 10.121.21.1 200')

      route('10.121.21.0/24').destroy
    end

    it 'reports the destination, gateway and metric it found' do
      profile(routes: '10.121.21.0/24 10.121.21.1 200')
      provider = route('10.121.21.0/24')

      expect(provider.destination).to eq('10.121.21.0/24')
      expect(provider.gateway).to eq('10.121.21.1')
      expect(provider.metric).to eq('200')
    end

    # destination, next hop, metric is the order NetworkManager stores them in.
    it 'writes a declared metric as the third token' do
      profile

      expect(described_class).to receive(:nmcli_list_add)
        .with('9c92fad9', 'ipv4.routes', '10.121.21.0/24 10.121.21.1 200')

      route('10.121.21.0/24', '10.121.21.1', 200).create
    end
  end

  # ipv4.routes is empty on every host in the fleet that has a default route,
  # because the default route is the connection gateway.
  describe 'the default route' do
    it 'exists when the connection has a gateway' do
      profile(gateway: '216.251.35.1')

      expect(route('default', '216.251.35.1')).to exist
    end

    it 'does not exist when it has none' do
      profile

      expect(route('default', '216.251.35.1')).not_to exist
    end

    it 'is written as the gateway, not as a list entry' do
      profile

      expect(described_class).to receive(:nmcli_connection_modify)
        .with('9c92fad9', 'ipv4.gateway', '216.251.35.1')
      expect(described_class).not_to receive(:nmcli_list_add)

      route('default', '216.251.35.1').create
    end

    it 'is removed by clearing the gateway' do
      profile(gateway: '216.251.35.1')

      expect(described_class).to receive(:nmcli_connection_modify)
        .with('9c92fad9', 'ipv4.gateway', '')

      route('default', '216.251.35.1').destroy
    end
  end

  describe 'an IPv6 destination' do
    it 'goes to the IPv6 properties' do
      allow(described_class).to receive(:nmcli_connection_lookup)
        .and_return('NAME' => 'eth1', 'UUID' => '9c92fad9', 'DEVICE' => 'eth1', 'ACTIVE' => 'no')
      allow(described_class).to receive(:nmcli_connection_show).and_return('connection.uuid' => '9c92fad9')

      expect(described_class).to receive(:nmcli_list_add)
        .with('9c92fad9', 'ipv6.routes', '2001:db8::/64 2001:db8::1')

      route('2001:db8::/64', '2001:db8::1').create
    end
  end

  describe 'without a profile for the device' do
    it 'says where the route was going to go' do
      allow(described_class).to receive(:nmcli_connection_lookup).and_return(nil)

      expect { route('10.121.21.0/24').create }
        .to raise_error(Puppet::Error, %r{no profile for eth1, so there is nowhere to put the route})
    end

    it 'removes nothing' do
      allow(described_class).to receive(:nmcli_connection_lookup).and_return(nil)

      expect(described_class).not_to receive(:nmcli_list_remove)

      route('10.121.21.0/24').destroy
    end
  end
end
