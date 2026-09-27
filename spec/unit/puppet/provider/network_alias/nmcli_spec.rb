require 'spec_helper'
require 'puppet/provider/network_alias/nmcli'

describe Puppet::Type.type(:network_alias).provider(:nmcli) do
  let(:resource) do
    Puppet::Type.type(:network_alias).new(
      name: 'myspc',
      ensure: :present,
      parent_device: 'lo',
      ipaddr: '64.29.155.171',
      netmask: '255.255.255.255',
      provider: :nmcli,
    )
  end

  let(:provider) { described_class.new(resource) }

  # The loopback connection of a web node: service addresses first and
  # 127.0.0.1/8 last, which is the order ifcfg aliases produce.
  def profile(addresses, active = 'yes')
    allow(described_class).to receive(:nmcli_connection_lookup)
      .and_return('NAME' => 'lo', 'UUID' => '0d986ff8', 'DEVICE' => 'lo', 'ACTIVE' => active)
    allow(described_class).to receive(:nmcli_connection_show)
      .and_return('connection.id' => 'lo', 'connection.uuid' => '0d986ff8',
                  'ipv4.addresses' => addresses)
    allow(described_class).to receive(:nmcli_device_reapply)
    # no ip binary in the test image, and no kernel to ask: the address is not
    # on the device yet, and it takes the label when it is put there
    allow(described_class).to receive(:addr_lookup).and_return({})
    allow(described_class).to receive(:addr_label).and_return('lo:myspc')
    allow(described_class).to receive(:addr_create)
    allow(described_class).to receive(:addr_change)
  end

  describe '#exists?' do
    it 'is true when the address is in the parent list' do
      profile('64.29.145.183/32, 64.29.155.171/32, 127.0.0.1/8')

      expect(provider).to exist
    end

    it 'is false when it is not' do
      profile('64.29.145.183/32, 127.0.0.1/8')

      expect(provider).not_to exist
    end

    it 'is false when NetworkManager has no profile for the parent' do
      allow(described_class).to receive(:nmcli_connection_lookup).and_return(nil)

      expect(provider).not_to exist
    end
  end

  describe '#create' do
    it 'adds one entry rather than writing the list' do
      profile('127.0.0.1/8')

      expect(described_class).to receive(:nmcli_connection_modify)
        .with('0d986ff8', '+ipv4.addresses', '64.29.155.171/32')
      expect(described_class).to receive(:nmcli_device_reapply).with('lo')

      provider.create
    end

    it 'derives the prefix from a netmask' do
      profile('127.0.0.1/8')
      allow(described_class).to receive(:nmcli_device_reapply)

      expect(described_class).to receive(:nmcli_connection_modify)
        .with(anything, anything, '64.29.155.171/32')

      provider.create
    end
  end

  describe '#destroy' do
    # `-ipv4.addresses 10.0.0.1` without the prefix exits 0 and removes
    # nothing, so the entry has to be named exactly as the profile carries it.
    it 'removes the entry with the prefix the profile carries' do
      profile('64.29.155.171/32, 127.0.0.1/8')

      expect(described_class).to receive(:nmcli_connection_modify)
        .with('0d986ff8', '-ipv4.addresses', '64.29.155.171/32')

      provider.destroy
    end

    it 'says nothing to nmcli when the parent has no profile' do
      allow(described_class).to receive(:nmcli_connection_lookup).and_return(nil)

      expect(described_class).not_to receive(:nmcli_connection_modify)

      provider.destroy
    end
  end

  describe '#flush' do
    it 'replaces the entry in one invocation when only the prefix changed' do
      profile('64.29.155.171/24, 127.0.0.1/8')
      provider.instance_variable_set(:@property_flush, prefix: 32)

      expect(described_class).to receive(:nmcli_connection_modify)
        .with('0d986ff8',
              '-ipv4.addresses', '64.29.155.171/24',
              '+ipv4.addresses', '64.29.155.171/32')

      provider.flush
    end

    # An alias has no identity in a NetworkManager profile beyond its address:
    # the label that used to be its name has nowhere to live. So a resource
    # whose address changed looks absent, Puppet creates the new entry, and
    # nothing connects it to the one it had before.
    it 'cannot connect a changed address to the entry it replaced' do
      profile('64.29.155.170/32, 127.0.0.1/8')

      expect(provider).not_to exist
      expect(provider.ipaddr).to be_nil
    end
  end

  # NetworkManager has nowhere to keep a label, so an alias label is live
  # kernel state: put on with ip before NetworkManager applies the profile,
  # and gone again after every reactivation until a run puts it back.
  describe 'the label' do
    it 'goes on before the profile is applied, which is when the address is not there yet' do
      profile('127.0.0.1/8')
      allow(described_class).to receive(:nmcli_connection_modify)

      expect(described_class).to receive(:addr_create)
        .with('64.29.155.171/32', 'dev', 'lo', 'label', 'lo:myspc').ordered
      expect(described_class).to receive(:nmcli_device_reapply).ordered

      provider.create
    end

    it 'is put back on an address a reactivation stripped it from' do
      profile('64.29.155.171/32, 127.0.0.1/8')
      allow(described_class).to receive(:addr_lookup)
        .and_return('local' => '64.29.155.171', 'ifa_label' => 'lo')

      expect(described_class).to receive(:addr_change).with('64.29.155.171/32', 'lo', 'lo:myspc')

      provider.apply_label
    end

    it 'is left alone when it is already right' do
      profile('64.29.155.171/32, 127.0.0.1/8')
      allow(described_class).to receive(:addr_lookup)
        .and_return('local' => '64.29.155.171', 'ifa_label' => 'lo:myspc')

      expect(described_class).not_to receive(:addr_change)
      expect(described_class).not_to receive(:addr_create)

      provider.apply_label
    end

    # A label that silently did not stick is drift nobody would see.
    it 'fails when the kernel did not take it' do
      profile('127.0.0.1/8')
      allow(described_class).to receive(:addr_label).and_return(nil)

      expect { provider.apply_label }
        .to raise_error(Puppet::Error, %r{kernel did not take the label "lo:myspc"})
    end
  end

  describe 'what it reports' do
    it 'reports the address and the mask it implies' do
      profile('64.29.155.171/32, 127.0.0.1/8')

      expect(provider.ipaddr).to eq('64.29.155.171')
      expect(provider.prefix).to eq('32')
      expect(provider.netmask).to eq('255.255.255.255')
    end

    # TYPE, ONBOOT and the rest were keys of the alias ifcfg file. Here they
    # belong to the parent connection, and reporting the parent's values as
    # this resource's own would be a claim about something it does not own.
    it 'says nothing about the properties that belong to the parent' do
      profile('64.29.155.171/32, 127.0.0.1/8')

      expect(provider.conn_type).to be_nil
      expect(provider.onboot).to be_nil
    end

    it 'does not apply a profile no device is running' do
      profile('127.0.0.1/8', 'no')
      allow(described_class).to receive(:nmcli_connection_modify)

      expect(described_class).not_to receive(:nmcli_device_reapply)

      provider.create
    end
  end
end
