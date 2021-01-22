require 'spec_helper'

describe Puppet::Type.type(:network_addr) do
  before(:each) do
    allow(Puppet::Util).to receive(:which).with('/sbin/ip').and_return('/sbin/ip')
    allow(Puppet::Type.type(:network_addr).provider(:ip)).to receive(:which).with('ip').and_return('/sbin/ip')
    allow(Puppet::Util::Execution).to receive(:execute)
      .with('/sbin/ip -details -o link show')
      .and_return(<<'EOL')
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
2: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/ipip 0.0.0.0 brd 0.0.0.0 promiscuity 0 \    ipip remote any local any ttl inherit nopmtudisc numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
3: ip6tnl0@NONE: <NOARP> mtu 1452 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/tunnel6 :: brd :: promiscuity 0 \    ip6tnl ip6ip6 remote :: local :: encaplimit 0 hoplimit 0 tclass 0x00 flowlabel 0x00000 (flowinfo 0x00000000) addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
8: eth0@if9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default \    link/ether 02:42:ac:11:00:03 brd ff:ff:ff:ff:ff:ff link-netnsid 0 promiscuity 0 \    veth addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
EOL
  end

  context 'check MAC address validation' do
    it do
      expect {
        described_class.new(ensure: :present,
                            title: '192.168.0.5',
                            hwaddr: '02:42:ac:11:00:03',
                            provider: :ip)
      }.not_to raise_error
    end

    it do
      expect(
        described_class.new(ensure: :present,
                            title: '192.168.0.5',
                            hwaddr: '02:42:ac:11:00:03',
                            provider: :ip)[:device],
      ).to eq('eth0')
    end

    it do
      expect(
        described_class.new(ensure: :present,
                            title: '192.168.0.5',
                            hwaddr: '02:42:ac:11:00:03',
                            label: 'internal',
                            provider: :ip)[:label],
      ).to eq('eth0:internal')
    end
  end
end
