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

  describe 'test different IPv6 network settings pass' do
    let(:resource_name) { 'lo:alias6' }
    let(:resource) do
      Puppet::Type.type(:network_alias).new(
        title: resource_name,
        ensure: :present,
        ipv6init: true,
        ipv6addr: '2001:1810:4240:3::17/128',
        ipv6_defaultgw: '2001:1810:4240:3::1',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias6
IPV6ADDR=2001:1810:4240:3::17/128
IPV6INIT=yes
IPV6_DEFAULTGW=2001:1810:4240:3::1
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

    context 'test address prefix length to be added to IPv6 address' do
      let(:resource) do
        Puppet::Type.type(:network_alias).new(
          title: resource_name,
          ensure: :present,
          ipv6init: true,
          ipv6addr: '2001:1810:4240:3::17',
          provider: :ip,
        )
      end
      let(:provider) do
        resource.provider = subject
      end

      it {
        expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias6
IPV6ADDR=2001:1810:4240:3::17/64
IPV6INIT=yes
EOL
      }
    end

    context 'test address prefix length to be added to IPv6 address' do
      let(:resource) do
        Puppet::Type.type(:network_alias).new(
          title: resource_name,
          ensure: :present,
          ipv6init: true,
          ipv6addr: '2001:1810:4240:3::17/64',
          ipv6_prefixlength: 80,
          provider: :ip,
        )
      end
      let(:provider) do
        resource.provider = subject
      end

      it {
        expect(provider.ifcfg_content).to eq(<<EOL)
DEVICE=lo:alias6
IPV6ADDR=2001:1810:4240:3::17/80
IPV6INIT=yes
EOL
      }
    end
  end

  describe 'test different network settings pass' do
    let(:ifcfg_content) { File.read(Dir.pwd + '/spec/fixtures/files/samples/ifcfg-lo:alias6') }
    let(:ifcfg) { File.open(Dir.pwd + '/spec/fixtures/files/ifcfg-lo:alias6', 'w', 0o600) }

    let(:resource_name) { 'alias6' }
    let(:resource) do
      Puppet::Type.type(:network_alias).new(
        name: resource_name,
        parent_device: 'lo',
        ensure: :present,
        ipaddr: '192.168.178.1',
        netmask: '255.255.255.224',
        conn_type: 'Ethernet',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo:alias6')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo:alias6')
        .and_return(ifcfg_content)
      allow(File).to receive(:open)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo:alias6', 'w', 0o600).and_return(ifcfg)
      allow(Puppet::Util).to receive(:which)
        .with('ifup').and_return('/etc/sysconfig/network-scripts/ifup')

      expect(provider.ifcfg_data).to eq(
        'device' => 'lo:alias6',
        'ipaddr' => '192.168.178.1',
        'netmask' => '255.255.255.224',
        'ipv6addr' => '2001:1810:4240:3::17/128',
        'ipv6addr_secondaries' => '2001:1810:4240:3::1/128 2001:1810:4240:3::2/128 2001:1810:4240:3::3/128',
        'ipv6init' => 'yes',
      )

      expect(ifcfg).to receive(:write)
        .with(<<EOF)
DEVICE=lo:alias6
TYPE=Ethernet
IPADDR=192.168.178.1
NETMASK=255.255.255.224
PREFIX=27
IPV6ADDR=2001:1810:4240:3::17/128
IPV6INIT=yes
IPV6ADDR_SECONDARIES="2001:1810:4240:3::1/128 2001:1810:4240:3::2/128 2001:1810:4240:3::3/128"
EOF

      expect(Puppet::Util::Execution).to receive(:execute)
        .with('/etc/sysconfig/network-scripts/ifup /etc/sysconfig/network-scripts/ifcfg-lo:alias6')

      provider.create
    }
  end
end
