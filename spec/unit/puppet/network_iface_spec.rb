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

  context 'check ipv6_setup validation' do
    let(:ifcfg_content) { <<EOT }
TYPE="Ethernet"
BOOTPROTO="none"
NAME="ens1f0"
DEVICE="ens1f0"
ONBOOT="yes"
IPADDR="10.100.16.7"
PREFIX="26"
GATEWAY="10.100.16.1"
EOT

    it do
      expect {
        described_class.new(ensure: :present,
                            name: 'eth0',
                            ipv6init: 'yes',
                            ipv6_setup: true)
      }.to raise_error(Puppet::Error, %r{ipv6_netprefix parameter must be specified})
    end

    it do
      expect {
        described_class.new(ensure: :present,
                            name: 'eth0',
                            ipv6init: 'yes',
                            ipv6_setup: true,
                            ipv6_netprefix: 'fe80::dea6:32ff')
      }.to raise_error(Puppet::Error, %r{error: IPADDR must be available})
    end

    it do
      expect {
        described_class.new(ensure: :present,
                            name: 'eth0',
                            ipaddr: '10.100.16.7',
                            ipv6init: 'yes',
                            ipv6_setup: true,
                            ipv6_netprefix: 'fe80:dea6:32ff',
                            provider: :ip)
      }.to raise_error(Puppet::Error, %r{ipv6_netprefix must be a valid IPv6 address when ending with host number})
    end

    it do
      expect(
        described_class.new(ensure: :present,
                            name: 'eth0',
                            ipaddr: '10.100.16.7',
                            ipv6init: 'yes',
                            ipv6_setup: true,
                            ipv6_netprefix: 'fe80::dea6:32ff',
                            provider: :ip)[:ipv6addr],
      ).to eq('fe80::dea6:32ff:0a64:1007/64')
    end

    it do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with('/etc/sysconfig/network-scripts/ifcfg-eth0')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-eth0')
        .and_return(ifcfg_content)

      expect(
        described_class.new(ensure: :present,
                            name: 'eth0',
                            ipv6init: 'yes',
                            ipv6_setup: true,
                            ipv6_netprefix: 'fe80::dea6:32ff',
                            provider: :ip)[:ipv6addr],
      ).to eq('fe80::dea6:32ff:0a64:1007/64')
    end
  end

  # ifcfg and NetworkManager are two vocabularies for one setting. A resource
  # written for ifcfg must stay in sync on a host whose profile reports the
  # NetworkManager word, or it would be rewritten on every run with neither
  # value being wrong.
  describe 'bootproto across the two vocabularies' do
    def bootproto(declared)
      described_class.new(name: 'eth0', bootproto: declared).property(:bootproto)
    end

    it 'accepts manual as what none and static asked for' do
      expect(bootproto('none')).to be_insync('manual')
      expect(bootproto('static')).to be_insync('manual')
    end

    it 'accepts auto as what dhcp and bootp asked for' do
      expect(bootproto('dhcp')).to be_insync('auto')
      expect(bootproto('bootp')).to be_insync('auto')
    end

    it 'still matches a value against itself' do
      expect(bootproto('manual')).to be_insync('manual')
      expect(bootproto('disabled')).to be_insync('disabled')
    end

    it 'does not make unrelated methods equivalent' do
      expect(bootproto('none')).not_to be_insync('auto')
      expect(bootproto('dhcp')).not_to be_insync('disabled')
    end

    it 'accepts the values only NetworkManager has a word for' do
      expect { described_class.new(name: 'eth0', bootproto: 'link-local') }.not_to raise_error
      expect { described_class.new(name: 'eth0', bootproto: 'nosuch') }.to raise_error(Puppet::Error)
    end
  end
end
