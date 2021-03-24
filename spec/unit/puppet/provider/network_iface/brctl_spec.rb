require 'spec_helper'
require 'ipaddr'

provider_class = Puppet::Type.type(:network_iface).provider(:brctl)
describe provider_class do
  let(:resource_name) { 'eth0' }
  let(:resource) do
    Puppet::Type.type(:network_iface).new(
      name: resource_name,
      ensure: :present,
      hwaddr: 'd4:85:64:7c:f8:28',
      provider: :brctl,
    )
  end
  let(:provider) do
    resource.provider = subject
  end

  before(:each) do
    allow(Puppet::Util).to receive(:which).with('/sbin/ip').and_return('/sbin/ip')
    allow(described_class).to receive(:which).with('ip').and_return('/sbin/ip')
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
        .and_return('3: o-hm0@o-bhm0: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/ether 62:01:09:c6:73:7d brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 65535 \    veth addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.linkinfo_show).to eq(
        'addrgenmode' => 'eui64',
        'brd' => 'ff:ff:ff:ff:ff:ff',
        'group' => 'default',
        'gso_max_size' => '65536',
        'gso_max_segs' => '65535',
        'link-flags' => ['BROADCAST', 'MULTICAST', 'M-DOWN'],
        'ifi_index' => '3',
        'ifname' => 'o-hm0',
        'iflink' => 'o-bhm0',
        'link-addr' => '62:01:09:c6:73:7d',
        'link-type' => 'link/ether',
        'maxmtu' => '65535',
        'minmtu' => '68',
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

  describe 'show bridge interface' do
    let(:resource_name) { 'br0' }
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: resource_name,
        ensure: :present,
        link_kind: :bridge,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show br0')
        .and_return('4: br0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/ether 6a:1c:c9:d7:f0:5e brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 65535 \    bridge forward_delay 1500 hello_time 200 max_age 2000 ageing_time 30000 stp_state 0 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.0:0:0:0:0:0 designated_root 8000.0:0:0:0:0:0 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    0.00 tcn_timer    0.00 topology_change_timer    0.00 gc_timer    0.00 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address 01:80:c2:00:00:00 mcast_snooping 1 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3125 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535') # rubocop:disable Metrics/LineLength

      expect(provider.linkinfo_show).to eq(
        'addrgenmode' => 'eui64',
        'brd' => 'ff:ff:ff:ff:ff:ff',
        'group' => 'default',
        'gso_max_size' => '65536',
        'gso_max_segs' => '65535',
        'link-flags' => ['BROADCAST', 'MULTICAST'],
        'ifi_index' => '4',
        'ifname' => 'br0',
        'iflink' => nil,
        'link-addr' => '6a:1c:c9:d7:f0:5e',
        'link-type' => 'link/ether',
        'maxmtu' => '65535',
        'minmtu' => '68',
        'mode' => 'DEFAULT',
        'mtu' => '1500',
        'numtxqueues' => '1',
        'numrxqueues' => '1',
        'promiscuity' => '0',
        'qdisc' => 'noop',
        'qlen' => '1000',
        'state' => 'DOWN',
        'link-kind' => :bridge,
        :bridge => {
          'ageing_time' => '30000',
          'bridge_id' => '8000.0:0:0:0:0:0',
          'designated_root' => '8000.0:0:0:0:0:0',
          'forward_delay' => '1500',
          'gc_timer' => '0.00',
          'group_address' => '01:80:c2:00:00:00',
          'group_fwd_mask' => '0',
          'hello_time' => '200',
          'hello_timer' => '0.00',
          'max_age' => '2000',
          'mcast_hash_elasticity' => '16',
          'mcast_hash_max' => '4096',
          'mcast_igmp_version' => '2',
          'mcast_last_member_count' => '2',
          'mcast_last_member_interval' => '100',
          'mcast_membership_interval' => '26000',
          'mcast_mld_version' => '1',
          'mcast_querier' => '0',
          'mcast_querier_interval' => '25500',
          'mcast_query_interval' => '12500',
          'mcast_query_response_interval' => '1000',
          'mcast_query_use_ifaddr' => '0',
          'mcast_router' => '1',
          'mcast_snooping' => '1',
          'mcast_startup_query_count' => '2',
          'mcast_startup_query_interval' => '3125',
          'mcast_stats_enabled' => '0',
          'nf_call_arptables' => '0',
          'nf_call_ip6tables' => '0',
          'nf_call_iptables' => '0',
          'priority' => '32768',
          'root_path_cost' => '0',
          'root_port' => '0',
          'stp_state' => '0',
          'tcn_timer' => '0.00',
          'topology_change' => '0',
          'topology_change_detected' => '0',
          'topology_change_timer' => '0.00',
          'vlan_default_pvid' => '1',
          'vlan_filtering' => '0',
          'vlan_protocol' => '802.1Q',
          'vlan_stats_enabled' => '0',
        },
      )
    }
  end
end
