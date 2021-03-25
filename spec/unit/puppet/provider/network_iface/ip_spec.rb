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
    allow(Puppet::Util).to receive(:which).and_call_original
    allow(Puppet::Util).to receive(:which).with('/sbin/ip').and_return('/sbin/ip')
    allow(Puppet::Util).to receive(:which).with('ifup').and_return('/etc/sysconfig/network-scripts/ifup')
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

      expect(provider.linkinfo_show).to eq(
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

  describe 'when hardware address provided' do
    let(:resource_name) { 'eth0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        hwaddr: 'd4:85:64:7c:f8:28',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it 'resource device is proper interface name' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show')
        .and_return(<<'EOF')
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
2: enp2s0f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:80 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0100000000000000000000373931364833
3: enp2s0f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:84 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000373931364833
4: ens1f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:28 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0100000000000000000000353435305448
5: ens1f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:2c brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000353435305448
EOF
      expect(resource[:device]).to eq('ens1f0')
    end

    it 'interface_name returns proper interface name' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show')
        .and_return(<<'EOF')
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
2: enp2s0f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:80 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0100000000000000000000373931364833
3: enp2s0f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:84 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000373931364833
4: ens1f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:28 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0100000000000000000000353435305448
5: ens1f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:2c brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000353435305448
EOF
      expect(provider.interface_name).to eq('ens1f0')
    end
  end

  describe 'when hardware address not provided' do
    let(:resource_name) { 'enp2s0f0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        device: 'ens1f1',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it 'interface_name returns nil' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show')
        .and_return(<<'EOF')
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
2: enp2s0f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:80 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0100000000000000000000373931364833
3: enp2s0f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:84 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000373931364833
4: ens1f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:28 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0100000000000000000000353435305448
5: ens1f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:2c brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000353435305448
EOF

      expect(provider.interface_name).to be_nil
    end

    it 'linkinfo_show returns info for interface behind device' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show ens1f1')
        .and_return('5: ens1f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether d4:85:64:7c:f8:2c brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000353435305448') # rubocop:disable Metrics/LineLength

      expect(provider.linkinfo_show).to eq(
        'addrgenmode' => 'none',
        'brd' => 'ff:ff:ff:ff:ff:ff',
        'group' => 'default',
        'gso_max_segs' => '65535',
        'gso_max_size' => '65513',
        'ifi_index' => '5',
        'iflink' => nil,
        'ifname' => 'ens1f1',
        'link-addr' => 'd4:85:64:7c:f8:2c',
        'link-flags' => ['BROADCAST', 'MULTICAST', 'UP', 'LOWER_UP'],
        'link-type' => 'link/ether',
        'mode' => 'DEFAULT',
        'mtu' => '1500',
        'numrxqueues' => '32',
        'numtxqueues' => '32',
        'portid' => '0200000000000000000000353435305448',
        'promiscuity' => '0',
        'qdisc' => 'mq',
        'qlen' => '1000',
        'state' => 'UP',
      )
    end

    it 'linkinfo_show returns info for interface behind name (if device not found)' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show ens1f1')
        .and_return('')
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show enp2s0f0')
        .and_return('3: enp2s0f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 78:e3:b5:02:a8:84 brd ff:ff:ff:ff:ff:ff promiscuity 0 addrgenmode none numtxqueues 32 numrxqueues 32 gso_max_size 65513 gso_max_segs 65535 portid 0200000000000000000000373931364833') # rubocop:disable Metrics/LineLength

      expect(provider.linkinfo_show).to eq(
        'addrgenmode' => 'none',
        'brd' => 'ff:ff:ff:ff:ff:ff',
        'group' => 'default',
        'gso_max_segs' => '65535',
        'gso_max_size' => '65513',
        'ifi_index' => '3',
        'iflink' => nil,
        'ifname' => 'enp2s0f1',
        'link-addr' => '78:e3:b5:02:a8:84',
        'link-flags' => ['BROADCAST', 'MULTICAST', 'UP', 'LOWER_UP'],
        'link-type' => 'link/ether',
        'mode' => 'DEFAULT',
        'mtu' => '1500',
        'numrxqueues' => '32',
        'numtxqueues' => '32',
        'portid' => '0200000000000000000000373931364833',
        'promiscuity' => '0',
        'qdisc' => 'mq',
        'qlen' => '1000',
        'state' => 'UP',
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
      resource.provider = subject
    end

    it 'returns an array of tun0 interface properties' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show tun0')
        .and_return('220: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1406 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 500\    link/none  promiscuity 0 minmtu 68 maxmtu 65535 \    tun type tun pi off vnet_hdr off persist off addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.linkinfo_show).to eq(
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
      resource.provider = subject
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

      expect(provider.linkinfo_show).to eq(
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
      resource.provider = subject
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show o-bhm0')
        .and_return('188: o-bhm0@o-hm0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/ether 5e:42:74:a2:8b:6e brd ff:ff:ff:ff:ff:ff promiscuity 0\    veth addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.linkinfo_show).to eq(
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

  describe 'linkinfo_show is empty on non-existing interface' do
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
      resource.provider = subject
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show o-bhm0')
        .and_return('')

      expect(provider.linkinfo_show).to eq({})
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
      resource.provider = subject
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
NAME=loopback
DEVICE=lo
ONBOOT=yes
IPADDR=127.0.0.1
NETMASK=255.0.0.0
NETWORK=127.0.0.0
BROADCAST=127.255.255.255
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
NAME=loopback
DEVICE=lo
ONBOOT=yes
IPADDR=127.0.0.1
NETMASK=255.0.0.0
NETWORK=127.0.0.0
BROADCAST=127.255.255.255
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
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo')
        .and_return(ifcfg_content)
      allow(File).to receive(:open)
        .with('/etc/sysconfig/network-scripts/ifcfg-lo', 'w', 0o600).and_return(ifcfg)

      expect(ifcfg).to receive(:write)
        .with(<<EOF)
TYPE=Ethernet
NAME=loopback
DEVICE=lo
ONBOOT=yes
IPADDR=127.0.0.53
PREFIX=27
NETMASK=255.255.255.224
NETWORK=127.0.0.32
BROADCAST=127.255.255.255
EOF

      expect(Puppet::Util::Execution).to receive(:execute)
        .with('/etc/sysconfig/network-scripts/ifup /etc/sysconfig/network-scripts/ifcfg-lo')

      provider.create
    }
  end

  describe 'test another network settings' do
    let(:ifcfg_content) { File.read(Dir.pwd + '/spec/fixtures/files/samples/ifcfg-ens1f0') }
    let(:ifcfg) { File.open(Dir.pwd + '/spec/fixtures/files/ifcfg-ens1f0', 'w', 0o600) }

    let(:resource_name) { 'eth0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        device: 'ens1f0',
        ipaddr: '10.100.16.7',
        prefix: 26,
        conn_type: 'Ethernet',
        dns: [
          '8.8.4.4',
          '8.8.8.8',
        ],
        ipv6addr_secondaries: [
          '2a03:2880:f1ff:83:face:b00c:0:25de',
          '2a00:1450:4001:828::2004',
        ],
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?)
        .with('/etc/sysconfig/network-scripts/ifcfg-eth0')
        .and_return(true)
      allow(File).to receive(:read)
        .with('/etc/sysconfig/network-scripts/ifcfg-eth0')
        .and_return(ifcfg_content)
      allow(File).to receive(:open)
        .with('/etc/sysconfig/network-scripts/ifcfg-eth0', 'w', 0o600).and_return(ifcfg)

      expect(provider.ifcfg_data).to eq(
        'bootproto' => 'none',
        'conn_name' => 'ens1f0',
        'conn_type' => 'Ethernet',
        'defroute' => 'yes',
        'device' => 'ens1f0',
        'dns' => ['10.100.0.10', '10.100.0.20'],
        'gateway' => '10.100.16.1',
        'ipaddr' => '10.100.16.7',
        'ipv6_autoconf' => 'yes',
        'ipv6addr_secondaries' => '2001:ba0:2020:bce5:678f:bcca:b152:a6ae/64 2001:ba0:2020:bce5:cdb:a034:601e:e952/64',
        'ipv6init' => 'yes',
        'onboot' => 'yes',
        'prefix' => '26',
      )

      expect(ifcfg).to receive(:write)
        .with(<<EOF)
TYPE=Ethernet
BOOTPROTO=none
DEFROUTE=yes
IPV6INIT=yes
NAME=ens1f0
DEVICE=ens1f0
ONBOOT=yes
IPADDR=10.100.16.7
PREFIX=26
NETMASK=255.255.255.192
GATEWAY=10.100.16.1
IPV6ADDR_SECONDARIES="2a03:2880:f1ff:83:face:b00c:0:25de 2a00:1450:4001:828::2004"
DNS1=8.8.4.4
DNS2=8.8.8.8
EOF

      expect(Puppet::Util::Execution).to receive(:execute)
        .with('/etc/sysconfig/network-scripts/ifup /etc/sysconfig/network-scripts/ifcfg-eth0')

      provider.create
    }
  end

  describe 'show address for PPP interface' do
    let(:resource_name) { 'ppp0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show ppp0')
        .and_return('633: ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1400 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 3\    link/ppp  promiscuity 0 minmtu 0 maxmtu 0 \    ppp addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o addr show ppp0')
        .and_return('633: ppp0    inet 192.168.53.13 peer 192.168.53.1/32 scope global ppp0\       valid_lft forever preferred_lft forever')

      expect(provider.addrinfo_show).to eq(
        [
          {
            'ifa_family' => 'inet',
            'ifa_index' => '633',
            'ifa_label' => 'ppp0',
            'ifname' => 'ppp0',
            'local' => '192.168.53.13',
            'peer' => '192.168.53.1',
            'preferred_lft' => 'forever',
            'prefixlen' => '32',
            'scope' => 'global',
            'valid_lft' => 'forever',
          },
        ],
      )
    }
  end

  describe 'show address for ETH interface' do
    let(:resource_name) { 'eth0' }
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
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show eth0')
        .and_return('4: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether dc:a6:32:7a:a1:ed brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 1500 addrgenmode eui64 numtxqueues 5 numrxqueues 5 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o addr show eth0')
        .and_return(<<'EOL')
4: eth0    inet 192.168.0.10/24 brd 192.168.0.255 scope global eth0\       valid_lft forever preferred_lft forever
4: eth0    inet6 fe80::250:56ff:fea5:bc68/64 scope link \       valid_lft forever preferred_lft forever
EOL

      expect(provider.addrinfo_show).to eq(
        [
          {
            'brd' => '192.168.0.255',
            'ifa_family' => 'inet',
            'ifa_index' => '4',
            'ifa_label' => 'eth0',
            'ifname' => 'eth0',
            'local' => '192.168.0.10',
            'preferred_lft' => 'forever',
            'prefixlen' => '24',
            'scope' => 'global',
            'valid_lft' => 'forever',
          },
          {
            'ifa_family' => 'inet6',
            'ifa_index' => '4',
            'ifname' => 'eth0',
            'local' => 'fe80::250:56ff:fea5:bc68',
            'preferred_lft' => 'forever',
            'prefixlen' => '64',
            'scope' => 'link',
            'valid_lft' => 'forever',
          },
        ],
      )
    }
  end

  # 2: eth0    inet 192.168.178.200/24 brd 192.168.178.255 scope global dynamic eth0\       valid_lft 663759sec preferred_lft 663759sec
  describe 'show address for ETH interface with flag' do
    let(:resource_name) { 'eth0' }
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
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show eth0')
        .and_return('2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether dc:a6:32:7a:a1:ed brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 1500 addrgenmode eui64 numtxqueues 5 numrxqueues 5 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o addr show eth0')
        .and_return('2: eth0    inet 192.168.178.200/24 brd 192.168.178.255 scope global dynamic eth0\       valid_lft 663759sec preferred_lft 663759sec')

      expect(provider.addrinfo_show).to eq(
        [
          {
            'brd' => '192.168.178.255',
            'dynamic' => 'on',
            'ifa_family' => 'inet',
            'ifa_index' => '2',
            'ifa_label' => 'eth0',
            'ifname' => 'eth0',
            'local' => '192.168.178.200',
            'preferred_lft' => '663759sec',
            'prefixlen' => '24',
            'scope' => 'global',
            'valid_lft' => '663759sec',
          },
        ],
      )
    }
  end
end
