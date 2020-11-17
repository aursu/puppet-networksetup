require 'spec_helper'

describe Puppet::Type.type(:network_iface).provider(:ip) do
  let(:iface) do
    <<-OS_OUTPUT
    17: tapcf33b841-6f@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master brqfc32e1e1-6f state UP mode DEFAULT group default qlen 1000\    link/ether ca:8c:b2:ee:35:fd brd ff:ff:ff:ff:ff:ff link-netnsid 8 promiscuity 1 \    veth \    bridge_slave state forwarding priority 32 cost 2 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8003 port_no 0x3 designated_port 32771 designated_cost 0 designated_bridge 8000.16:e8:8a:82:ba:4e designated_root 8000.16:e8:8a:82:ba:4e hold_timer    0.00 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
    OS_OUTPUT
  end
  let(:resource_name) { 'o-hm0' }
  let(:resource) do
    Puppet::Type.type(:network_iface).new(
      name: resource_name,
      ensure: :present,
      type: 'veth',
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
    allow(described_class).to receive(:which).with('ip').and_return('/sbin/ip')
  end


  describe 'new veth interface' do
    it do
      expect(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip link add o-hm0 type veth peer name o-bhm0')
      provider.create
    end
  end
end
