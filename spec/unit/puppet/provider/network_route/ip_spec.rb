require 'spec_helper'
require 'puppet/provider/network_route/ip'

describe Puppet::Type.type(:network_route).provider(:ip) do
  let(:provider) { described_class.new(resource) }
  let(:resource) do
    Puppet::Type.type(:network_route).new(
      name: '10.100.16.0/24 via 192.168.1.1 dev eth0',
      ensure: :present,
      destination: '10.100.16.0/24',
      device: 'eth0',
      gateway: '192.168.1.1',
      provider: :ip,
    )
  end

  before(:each) do
    allow(described_class).to receive(:ip_caller).and_return(true)
    allow(described_class).to receive(:route_create).and_return(true)
    allow(described_class).to receive(:route_delete).and_return(true)
    allow(File).to receive(:exist?).and_return(true)
    allow(File).to receive(:open)
  end

  describe '#create' do
    it 'creates a route and writes to the config file' do
      expect(described_class).to receive(:route_create).with('10.100.16.0/24', 'eth0', '192.168.1.1')
      expect(described_class).to receive(:write_route_config).with('eth0', '10.100.16.0/24', '192.168.1.1')
      provider.create
    end
  end

  describe '#destroy' do
    it 'deletes a route and removes it from config file' do
      allow(provider).to receive(:route_lookup).and_return({ 'dst' => '10.100.16.0/24' })
      expect(described_class).to receive(:route_delete).with('10.100.16.0/24', 'eth0', '192.168.1.1')
      expect(described_class).to receive(:remove_route_from_config).with('eth0', '10.100.16.0/24')
      provider.destroy
    end
  end

  describe '#flush' do
    before(:each) do
      provider.instance_variable_set(:@property_hash, { ensure: :present, device: 'eth0', gateway: '192.168.1.1' })
      provider.instance_variable_set(:@property_flush, { device: 'eth1', gateway: '192.168.1.2' })
      allow(File).to receive(:exist?).with('/etc/sysconfig/network-scripts/route-eth0').and_return(true)
      allow(File).to receive(:readlines).with('/etc/sysconfig/network-scripts/route-eth0').and_return(["10.100.16.0/24 via 192.168.1.1\n"])
      allow(File).to receive(:open)
      allow(File).to receive(:delete).with('/etc/sysconfig/network-scripts/route-eth0')
    end

    it 'updates the route and config file' do
      expect(described_class).to receive(:route_delete).with('10.100.16.0/24', 'eth0', '192.168.1.1')
      expect(described_class).to receive(:remove_route_from_config).with('eth0', '10.100.16.0/24')
      expect(described_class).to receive(:route_create).with('10.100.16.0/24', 'eth1', '192.168.1.2')
      expect(described_class).to receive(:write_route_config).with('eth1', '10.100.16.0/24', '192.168.1.2')
      provider.flush
    end
  end

  describe '#flush to check delete' do
    before(:each) do
      provider.instance_variable_set(:@property_hash, { ensure: :present, device: 'eth0', gateway: '192.168.1.1' })
      provider.instance_variable_set(:@property_flush, { device: 'eth1', gateway: '192.168.1.2' })
      allow(File).to receive(:exist?).with('/etc/sysconfig/network-scripts/route-eth0').and_return(true)
      allow(File).to receive(:readlines).with('/etc/sysconfig/network-scripts/route-eth0').and_return([])
      allow(File).to receive(:readlines).with('/etc/sysconfig/network-scripts/route-eth1').and_return([])
    end

    it 'deletes the config file when no routes remain' do
      expect(File).to receive(:delete).with('/etc/sysconfig/network-scripts/route-eth0')
      provider.flush
    end

    it 'write route into eth1' do
      allow(File).to receive(:delete).with('/etc/sysconfig/network-scripts/route-eth0')
      file_mock = instance_double('file')
      expect(File).to receive(:open).with('/etc/sysconfig/network-scripts/route-eth1', 'a').and_yield(file_mock)
      expect(file_mock).to receive(:puts).with('10.100.16.0/24 via 192.168.1.2')
      provider.flush
    end
  end

  describe '#write_route_config' do
    let(:config_file) { '/etc/sysconfig/network-scripts/route-eth0' }

    it 'creates a route file if it does not exist' do
      allow(File).to receive(:exist?).with(config_file).and_return(false)
      expect(File).to receive(:open).with(config_file, 'w')
      described_class.write_route_config('eth0', '10.100.16.0/24', '192.168.1.1')
    end
  end

  describe '#remove_route_from_config' do
    let(:config_file) { '/etc/sysconfig/network-scripts/route-eth0' }

    it 'removes a route from the config file' do
      allow(File).to receive(:exist?).with(config_file).and_return(true)
      allow(File).to receive(:readlines).with(config_file).and_return(["10.100.16.0/24 via 192.168.1.1\n", "10.100.18.0/24 via 192.168.1.1\n"])
      file_mock = instance_double('file')

      expect(File).to receive(:open).with(config_file, 'w').and_yield(file_mock)
      expect(file_mock).to receive(:write).with("10.100.18.0/24 via 192.168.1.1\n")

      described_class.remove_route_from_config('eth0', '10.100.16.0/24')
    end

    it 'deletes the file if it is empty after removal' do
      allow(File).to receive(:exist?).with(config_file).and_return(true)
      allow(File).to receive(:readlines).with(config_file).and_return(["10.100.16.0/24 via 192.168.1.1\n"])
      allow(File).to receive(:open).with(config_file, 'w')
      expect(File).to receive(:delete).with(config_file)
      described_class.remove_route_from_config('eth0', '10.100.16.0/24')
    end
  end

  describe '#prefetch' do
    let(:resources) do
      {
        '10.100.16.0/24' => Puppet::Type.type(:network_route).new(
          name: '10.100.16.0/24',
          ensure: :present,
          destination: '10.100.16.0/24',
          lookup_device: '10.50.16.0/24',
          provider: :ip,
        )
      }
    end

    let(:existing_provider) do
      described_class.new(
        name: '10.100.16.0/24',
        ensure: :present,
        destination: '10.100.16.0/24',
        device: 'eth0',
        gateway: '192.168.1.1',
      )
    end

    before(:each) do
      allow(described_class).to receive(:instances).and_return([existing_provider])
      allow(described_class).to receive(:get_device_by_network).with('10.50.16.0/24').and_return(['eth1'])
    end

    it 'calls instances' do
      expect(described_class).to receive(:instances).and_return([existing_provider])
      described_class.prefetch(resources)
    end

    it 'assigns provider if resource exists' do
      described_class.prefetch(resources)
      expect(resources['10.100.16.0/24'].provider).to eq(existing_provider)
    end

    it 'sets ensure => :present for existing resources' do
      described_class.prefetch(resources)
      expect(resources['10.100.16.0/24'][:ensure]).to eq(:present)
    end
  end
end
