require 'spec_helper'

describe Puppet::Type.type(:network_alias) do
  context 'check device validation' do
    it do
      expect {
        described_class.new(
          title: 'alias',
          ensure: :present,
        )
      }.to raise_error(Puppet::Error, %r{error: didn't specify device})
    end
  end

  context 'check device validation with device set' do
    it do
      expect {
        described_class.new(
          title: 'alias',
          device: 'lo:alias2',
          ensure: :present,
        )
      }.to raise_error(Puppet::Error, %r{error: didn't specify ipaddr and ipv6addr address})
    end

    it do
      expect {
        described_class.new(
          title: 'eth0:alias',
          ensure: :present,
        )
      }.to raise_error(Puppet::Error, %r{error: didn't specify ipaddr and ipv6addr address})
    end
  end

  context 'check ipaddr validation' do
    it do
      expect {
        described_class.new(
          title: 'eth1:alias',
          ensure: :present,
          ipaddr: '192.168.0.5',
          provider: :ip,
        )
      }.not_to raise_error
    end
  end

  # An alias is an entry of the parent's connection profile, so the parent has
  # to exist before there is anything to add an address to.
  describe 'ordering against the parent interface' do
    let(:catalog) { Puppet::Resource::Catalog.new }

    it 'runs after the network_iface it belongs to' do
      parent = Puppet::Type.type(:network_iface).new(name: 'lo')
      alias_resource = described_class.new(name: 'myspc', parent_device: 'lo', ipaddr: '10.0.0.1')
      catalog.add_resource(parent, alias_resource)

      expect(alias_resource.autorequire.map { |edge| edge.source.to_s }).to include('Network_iface[lo]')
    end

    it 'requires nothing when the parent is not in the catalogue' do
      alias_resource = described_class.new(name: 'myspc', parent_device: 'lo', ipaddr: '10.0.0.1')
      catalog.add_resource(alias_resource)

      expect(alias_resource.autorequire).to be_empty
    end
  end
end
