require 'spec_helper'
require 'ipaddr'

provider_class = Puppet::Type.type(:network_addr).provider(:ip)
describe provider_class do
  before(:each) do
    allow(Puppet::Util).to receive(:which).and_call_original
    allow(Puppet::Util).to receive(:which).with('/sbin/ip').and_return('/sbin/ip')
    allow(described_class).to receive(:which).with('ip').and_return('/sbin/ip')
  end

  describe 'check path to config' do
    let(:resource_name) { '172.17.0.2' }
    let(:resource) do
      Puppet::Type.type(:network_addr).new(
        title: resource_name,
        ensure: :present,
        device: 'lo',
        provider: :ip,
      )
    end
    let(:provider) do
      resource.provider = subject
    end

    it {
      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o link show')
        .and_return(<<'EOL')
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
2: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/ipip 0.0.0.0 brd 0.0.0.0 promiscuity 0 \    ipip remote any local any ttl inherit nopmtudisc numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
3: ip6tnl0@NONE: <NOARP> mtu 1452 qdisc noop state DOWN mode DEFAULT group default qlen 1000\    link/tunnel6 :: brd :: promiscuity 0 \    ip6tnl ip6ip6 remote :: local :: encaplimit 0 hoplimit 0 tclass 0x00 flowlabel 0x00000 (flowinfo 0x00000000) addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
8: eth0@if9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default \    link/ether 02:42:ac:11:00:03 brd ff:ff:ff:ff:ff:ff link-netnsid 0 promiscuity 0 \    veth addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
EOL

      allow(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip -details -o addr show')
        .and_return(<<'EOL')
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
1: lo    inet 192.168.178.1/27 brd 192.168.178.31 scope global lo:alias6\       valid_lft forever preferred_lft forever
1: lo    inet6 ::1/128 scope host \       valid_lft forever preferred_lft forever
8: eth0    inet 172.17.0.3/16 brd 172.17.255.255 scope global eth0\       valid_lft forever preferred_lft forever
8: eth0    inet6 2001:db8:1::242:ac11:3/64 scope global nodad \       valid_lft forever preferred_lft forever
8: eth0    inet6 fe80::42:acff:fe11:3/64 scope link \       valid_lft forever preferred_lft forever
EOL

      expect(provider.ifcfg_data).to eq(
        'ifa_family' => 'inet',
        'ifa_index' => '1',
        'ifa_label' => 'lo',
        'ifname' => 'lo',
        'local' => '127.0.0.1',
        'preferred_lft' => 'forever',
        'prefixlen' => '8',
        'scope' => 'host',
        'valid_lft' => 'forever',
      )

      expect(Puppet::Util::Execution).to receive(:execute)
        .with('/sbin/ip addr add 172.17.0.2 brd \+ dev lo scope host')

      provider.create
    }
  end
end
