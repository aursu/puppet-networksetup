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
end
