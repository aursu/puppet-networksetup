require 'spec_helper'
require 'ipaddr'

provider_class = Puppet::Type.type(:network_alias).provider(:ip)
describe provider_class do
  describe 'check path to config' do
    let(:resource_name) { 'lo:osdev' }
    let(:resource) do
      Puppet::Type.type(:network_alias).new(
        title: resource_name,
        ipaddr: '127.0.0.5',
        ensure: :present,
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      expect(provider.config_path).to eq('/etc/sysconfig/network-scripts/ifcfg-lo:osdev')
    }
  end

  describe 'test different IPv4 network settings pass' do
    let(:resource_name) { 'lo:alias' }
    let(:resource) do
      Puppet::Type.type(:network_alias).new(
        title: resource_name,
        ensure: :present,
        ipaddr: '127.0.0.53',
        netmask: '255.255.255.224',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias
IPADDR=127.0.0.53
NETMASK=255.255.255.224
PREFIX=27
EOL
    }
  end

  describe 'test different IPv4 network settings pass' do
    let(:resource_name) { 'lo:alias6' }
    let(:resource) do
      Puppet::Type.type(:network_alias).new(
        title: resource_name,
        ensure: :present,
        ipv6init: true,
        ipv6addr: '2001:1810:4240:3::17/128',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias6
NETMASK=ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
PREFIX=128
IPV6ADDR=2001:1810:4240:3::17/128
IPV6INIT=yes
EOL
    }

    context 'With both IPv4 and IPv6 settings' do
      let(:resource) do
        Puppet::Type.type(:network_alias).new(
          title: resource_name,
          ensure: :present,
          ipv6init: true,
          ipv6addr: '2001:1810:4240:3::17/128',
          ipaddr: '127.0.0.53',
          netmask: '255.255.255.224',
          provider: :ip,
        )
      end

      it {
        expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias6
IPADDR=127.0.0.53
NETMASK=255.255.255.224
PREFIX=27
IPV6ADDR=2001:1810:4240:3::17/128
IPV6INIT=yes
EOL
      }
    end

    context 'With additional IPv6 settings' do
      let(:resource) do
        Puppet::Type.type(:network_alias).new(
          title: resource_name,
          ensure: :present,
          ipv6init: true,
          ipv6addr: '2001:1810:4240:3::17/128',
          ipaddr: '127.0.0.53',
          netmask: '255.255.255.224',
          ipv6addr_secondaries: [
            '2001:1810:4240:3::1/128',
            '2001:1810:4240:3::2/128',
            '2001:1810:4240:3::3/128',
          ],
          provider: :ip,
        )
      end

      it {
        expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias6
IPADDR=127.0.0.53
NETMASK=255.255.255.224
PREFIX=27
IPV6ADDR=2001:1810:4240:3::17/128
IPV6INIT=yes
IPV6ADDR_SECONDARIES="2001:1810:4240:3::1/128 2001:1810:4240:3::2/128 2001:1810:4240:3::3/128"
EOL
      }
    end
  end
end
