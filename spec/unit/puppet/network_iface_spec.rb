require 'spec_helper'

describe Puppet::Type.type(:network_iface) do
  context 'with wrong connection type' do
    it do
      expect {
        described_class.new(
          name: 'eth0',
          conn_type: 'WLAN',
          ensure: :present,
        )
      }.to raise_error(Puppet::ResourceError, %r{Invalid value})
    end
  end

  context 'with invalid device name' do
    it do
      expect {
        described_class.new(
          name: 'eth0',
          device: 'eth0:wlan1',
          ensure: :present,
        )
      }.to raise_error(Puppet::Error, %r{error: invalid device name})
    end
  end

  context 'check IP address validation' do
    it do
      expect {
        described_class.new(
          name: 'eth0',
          ipaddr: '192.168.178.200',
          ensure: :present,
          provider: :ip,
        )
      }.not_to raise_error
    end

    it 'with wrong IP address for ipaddr' do
      expect {
        described_class.new(
          name: 'eth0',
          ipaddr: '192.168.178.300',
          ensure: :present,
          provider: :ip,
        )
      }.to raise_error(Puppet::Error, %r{Wrong IP address})
    end

    it 'with none for gateway' do
      expect {
        described_class.new(
          name: 'eth0',
          ipaddr: '192.168.178.200',
          gateway: 'none',
          ensure: :present,
          provider: :ip,
        )
      }.not_to raise_error
    end

    it 'with wrong IP address for gateway' do
      expect {
        described_class.new(
          name: 'eth0',
          gateway: '192.168.178.300',
          ensure: :present,
          provider: :ip,
        )
      }.to raise_error(Puppet::Error, %r{Wrong IP address})
    end
  end

  context 'check resource validation' do
    it do
      expect {
        described_class.new(
          name: 'o-bhm0',
          link_kind: :veth,
          ensure: :present,
        )
      }.to raise_error(Puppet::Error, %r{error: peer name property must be specified for VETH tunnel})
    end
  end

  context 'check switch property' do
    it do
      expect(
        described_class.new(ensure: :present,
                            title: 'eth0',
                            ipv6init: true,
                            provider: :ip)[:ipv6init],
      ).to eq('yes')
    end

    it do
      expect(
        described_class.new(ensure: :present,
                            title: 'eth0',
                            ipv6init: '1',
                            provider: :ip)[:ipv6init],
      ).to eq('yes')
    end

    it do
      expect(
        described_class.new(ensure: :present,
                            title: 'eth0',
                            ipv6init: 'no',
                            provider: :ip)[:ipv6init],
      ).to eq('no')
    end
  end
end
