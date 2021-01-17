require 'spec_helper'
require 'ipaddr'

provider_class = Puppet::Type.type(:network_iface).provider(:ip)
describe provider_class do
  let(:resource_name) { 'o-hm0' }
  let(:resource) do
    Puppet::Type.type(:network_iface).new(
      name: resource_name,
      ensure: :present,
      link_kind: 'veth',
      peer_name: 'o-bhm0',
    )
  end

  let(:provider) do
    provider = subject
    provider.resource = resource
    provider
  end

  before(:each) do
    allow(Puppet::Util).to receive(:which).with('ip').and_return('/sbin/ip')
    allow(Puppet::Util).to receive(:which).with('/sbin/ip').and_return('/sbin/ip')
    allow(described_class).to receive(:which).with('ip').and_return('/sbin/ip')
  end

  describe 'new veth interface' do
    let(:ifcfg) { File.open(Dir.pwd + '/spec/fixtures/files/ifcfg-o-hm0', 'w', 0o600) }
    it do
      allow(File).to receive(:open)
        .with('/etc/sysconfig/network-scripts/ifcfg-o-hm0', 'w', 0o600).and_return(ifcfg)
      expect(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip link add o-hm0 type veth peer name o-bhm0')
      provider.create
    end
  end

  describe 'show ppp0 interface' do
    let(:resource_name) { 'ppp0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it 'returns an array of ppp0 interface properties' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show ppp0')
        .and_return('207: ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1400 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 3\    link/ppp  promiscuity 0 minmtu 0 maxmtu 0 \    ppp addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.provider_show).to eq(
        'addrgenmode' => 'eui64',
        'group' => 'default',
        'gso_max_segs' => '65535',
        'gso_max_size' => '65536',
        'link-flags' => ['POINTOPOINT', 'MULTICAST', 'NOARP', 'UP', 'LOWER_UP'],
        'ifi_index' => '207',
        'iflink' => nil,
        'ifname' => 'ppp0',
        'link-addr' => '',
        'link-type' => 'link/ppp',
        'maxmtu' => '0',
        'minmtu' => '0',
        'mode' => 'DEFAULT',
        'mtu' => '1400',
        'numrxqueues' => '1',
        'numtxqueues' => '1',
        'promiscuity' => '0',
        'qdisc' => 'fq_codel',
        'qlen' => '3',
        'state' => 'UNKNOWN',
        'link-kind' => :ppp,
        ppp: {},
      )
    end
  end

  describe 'show tun0 interface' do
    let(:resource_name) { 'tun0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it 'returns an array of tun0 interface properties' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show tun0')
        .and_return('220: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1406 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 500\    link/none  promiscuity 0 minmtu 68 maxmtu 65535 \    tun type tun pi off vnet_hdr off persist off addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.provider_show).to eq(
        'addrgenmode' => 'eui64',
        'group' => 'default',
        'gso_max_segs' => '65535',
        'gso_max_size' => '65536',
        'link-flags' => ['POINTOPOINT', 'MULTICAST', 'NOARP', 'UP', 'LOWER_UP'],
        'ifi_index' => '220',
        'iflink' => nil,
        'ifname' => 'tun0',
        'link-addr' => '',
        'link-type' => 'link/none',
        'maxmtu' => '65535',
        'minmtu' => '68',
        'mode' => 'DEFAULT',
        'mtu' => '1406',
        'numrxqueues' => '1',
        'numtxqueues' => '1',
        'promiscuity' => '0',
        'qdisc' => 'fq_codel',
        'qlen' => '500',
        'state' => 'UNKNOWN',
        'link-kind' => :tun,
        tun: {
          'persist' => 'off',
          'pi' => 'off',
          'type' => 'tun',
          'vnet_hdr' => 'off',
        },
      )
    end
  end

  describe 'show veth interface' do
    let(:resource_name) { 'tapcf33b841-6f' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    # rubocop:disable Metrics/LineLength
    # 17: tapcf33b841-6f@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master brqfc32e1e1-6f state UP mode DEFAULT group default qlen 1000
    #    link/ether ca:8c:b2:ee:35:fd brd ff:ff:ff:ff:ff:ff link-netnsid 8 promiscuity 1
    #    veth
    #    bridge_slave state forwarding priority 32 cost 2 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8003 port_no 0x3 designated_port 32771 designated_cost 0 designated_bridge 8000.16:e8:8a:82:ba:4e designated_root 8000.16:e8:8a:82:ba:4e hold_timer    0.00 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535')
    # rubocop:enable Metrics/LineLength

    it 'returns an array of veth interface properties' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show tapcf33b841-6f')
        .and_return('17: tapcf33b841-6f@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master brqfc32e1e1-6f state UP mode DEFAULT group default qlen 1000\    link/ether ca:8c:b2:ee:35:fd brd ff:ff:ff:ff:ff:ff link-netnsid 8 promiscuity 1 \    veth \    bridge_slave state forwarding priority 32 cost 2 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8003 port_no 0x3 designated_port 32771 designated_cost 0 designated_bridge 8000.16:e8:8a:82:ba:4e designated_root 8000.16:e8:8a:82:ba:4e hold_timer    0.00 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.provider_show).to eq(
        'addrgenmode' => 'eui64',
        'brd' => 'ff:ff:ff:ff:ff:ff',
        'slave-kind' => :bridge_slave,
        'group' => 'default',
        'gso_max_segs' => '65535',
        'gso_max_size' => '65536',
        'link-flags' => ['BROADCAST', 'MULTICAST', 'UP', 'LOWER_UP'],
        'ifi_index' => '17',
        'iflink' => 'if2',
        'ifname' => 'tapcf33b841-6f',
        'link-addr' => 'ca:8c:b2:ee:35:fd',
        'link-netnsid' => '8',
        'link-type' => 'link/ether',
        'master' => 'brqfc32e1e1-6f',
        'mode' => 'DEFAULT',
        'mtu' => '1450',
        'numrxqueues' => '1',
        'numtxqueues' => '1',
        'promiscuity' => '1',
        'qdisc' => 'noqueue',
        'qlen' => '1000',
        'state' => 'UP',
        'link-kind' => :veth,
        :bridge_slave => {
          'config_pending' => '0',
          'cost' => '2',
          'designated_bridge' => '8000.16:e8:8a:82:ba:4e',
          'designated_cost' => '0',
          'designated_port' => '32771',
          'designated_root' => '8000.16:e8:8a:82:ba:4e',
          'fastleave' => 'off',
          'flood' => 'on',
          'forward_delay_timer' => '0.00',
          'guard' => 'off',
          'hairpin' => 'off',
          'hold_timer' => '0.00',
          'learning' => 'on',
          'mcast_fast_leave' => 'off',
          'mcast_flood' => 'on',
          'mcast_router' => '1',
          'message_age_timer' => '0.00',
          'port_id' => '0x8003',
          'port_no' => '0x3',
          'priority' => '32',
          'proxy_arp' => 'off',
          'proxy_arp_wifi' => 'off',
          'root_block' => 'off',
          'state' => 'forwarding',
          'topology_change_ack' => '0',
        },
        :veth => {},
      )
    end
  end

  describe 'show non-bridged veth interface' do
    let(:resource_name) { 'o-bhm0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        link_kind: :veth,
        peer_name: 'o-hm0',
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show o-bhm0')
        .and_return('188: o-bhm0@o-hm0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/ether 5e:42:74:a2:8b:6e brd ff:ff:ff:ff:ff:ff promiscuity 0\    veth addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.provider_show).to eq(
        'addrgenmode' => 'eui64',
        'brd' => 'ff:ff:ff:ff:ff:ff',
        'group' => 'default',
        'gso_max_size' => '65536',
        'gso_max_segs' => '65535',
        'link-flags' => ['BROADCAST', 'MULTICAST'],
        'ifi_index' => '188',
        'ifname' => 'o-bhm0',
        'iflink' => 'o-hm0',
        'link-addr' => '5e:42:74:a2:8b:6e',
        'link-type' => 'link/ether',
        'mode' => 'DEFAULT',
        'mtu' => '1500',
        'numtxqueues' => '1',
        'numrxqueues' => '1',
        'promiscuity' => '0',
        'qdisc' => 'noop',
        'qlen' => '1000',
        'state' => 'DOWN',
        'link-kind' => :veth,
        :veth => {},
      )
    }
  end

  describe 'empty hash on non-existing interface' do
    let(:resource_name) { 'o-bhm0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        link_kind: :veth,
        peer_name: 'o-hm0',
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show o-bhm0')
        .and_return('')

      expect(provider.provider_show).to eq(
        {}
      )
    }
  end

  describe 'check validation methods' do
    subject(:provider) { described_class.new }

    # good IP address
    it {
      expect(provider.validate_ip('192.168.178.2')).to eq(IPAddr.new('192.168.178.2'))
    }

    # wrong IP address
    it {
      expect(provider.validate_ip('192.168.178.400')).to eq(nil)
    }

    # good MAC address
    it {
      expect(provider.validate_mac('02:42:ac:11:00:03')).to eq(0)
    }

    # wrong MAC address
    it {
      expect(provider.validate_mac('02:42:ac:11:00:0z')).to eq(nil)
    }
  end

  describe 'test loopback interface configuration parsing' do
    let(:ifcfg_content) { File.read(Dir.pwd + '/spec/fixtures/files/samples/ifcfg-lo') }
    let(:ifcfg) { File.open(Dir.pwd + '/spec/fixtures/files/ifcfg-lo', 'w', 0o600) }

    let(:resource_name) { 'lo' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it {
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(ifcfg_content)

      expect(provider.ifcfg_data).to eq(
        'broadcast' => '127.255.255.255',
        'conn_name' => 'loopback',
        'device'    => 'lo',
        'ipaddr'    => '127.0.0.1',
        'netmask'   => '255.0.0.0',
        'network'   => '127.0.0.0',
        'onboot'    => 'yes',
      )

      expect(provider.ifcfg_content).to eq(<<EOF)
DEVICE=lo
IPADDR=127.0.0.1
NETMASK=255.0.0.0
NETWORK=127.0.0.0
BROADCAST=127.255.255.255
ONBOOT=yes
NAME=loopback
EOF
    }

    it {
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(ifcfg_content)
      allow(File).to receive(:open)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo', 'w', 0o600).and_return(ifcfg)

      expect(ifcfg).to receive(:write)
        .with(<<EOF)
DEVICE=lo
IPADDR=127.0.0.1
NETMASK=255.0.0.0
NETWORK=127.0.0.0
BROADCAST=127.255.255.255
ONBOOT=yes
NAME=loopback
EOF

      provider.create
    }
  end

  describe 'test different network settings pass' do
    let(:ifcfg_content) { File.read(Dir.pwd + '/spec/fixtures/files/samples/ifcfg-lo') }
    let(:ifcfg) { File.open(Dir.pwd + '/spec/fixtures/files/ifcfg-lo', 'w', 0o600) }

    let(:resource_name) { 'lo' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        ipaddr: '127.0.0.53',
        netmask: '255.255.255.224',
        network: '127.0.0.32',
        provider: :ip,
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it {
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(ifcfg_content)
      allow(File).to receive(:open)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo', 'w', 0o600).and_return(ifcfg)

      expect(ifcfg).to receive(:write)
        .with(<<EOF)
DEVICE=lo
IPADDR=127.0.0.53
NETMASK=255.255.255.224
NETWORK=127.0.0.32
BROADCAST=127.255.255.255
ONBOOT=yes
NAME=loopback
EOF

      provider.create
    }
  end
end
