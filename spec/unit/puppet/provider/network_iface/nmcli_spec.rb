require 'spec_helper'
require 'puppet/provider/network_iface/nmcli'

describe Puppet::Type.type(:network_iface).provider(:nmcli) do
  let(:ip_provider) { Puppet::Type.type(:network_iface).provider(:ip) }

  # Which provider a release resolves to is the one thing that has to be proven
  # rather than reasoned about: an interface managed by the wrong one writes its
  # configuration where nothing reads it and reports success.
  #
  # It is proven through `default?` and `specificity` rather than through
  # `defaultprovider`, because `commands` adds an implicit "this binary exists"
  # confine and the test image carries neither `ip` nor `nmcli` — there, every
  # provider is unsuitable and `defaultprovider` is nil whatever the facts say.
  describe 'provider selection' do
    def with_release(major)
      facter = Puppet.runtime[:facter]
      allow(facter).to receive(:value).and_call_original
      allow(facter).to receive(:value).with(:osfamily).and_return('RedHat')
      allow(facter).to receive(:value).with(:operatingsystemmajrelease).and_return(major)
      yield
    end

    it 'is a default on EL10, which has no network-scripts' do
      with_release('10') do
        expect(described_class).to be_default
      end
    end

    it 'is not a default on EL9' do
      with_release('9') do
        expect(described_class).not_to be_default
      end
    end

    it 'is not a default on EL8' do
      with_release('8') do
        expect(described_class).not_to be_default
      end
    end

    it 'leaves EL8 and EL9 to the ip provider' do
      with_release('9') { expect(ip_provider).to be_default }
      with_release('8') { expect(ip_provider).to be_default }
    end

    # On EL10 both providers are defaults - the ip one claims the whole RedHat
    # family - so the winner is the more specific, and that has to stay true.
    it 'outranks the ip provider where both apply' do
      with_release('10') do
        expect(described_class).to be_default
        expect(ip_provider).to be_default
      end

      expect(described_class.specificity).to be > ip_provider.specificity
    end
  end

  describe '#exists?' do
    let(:resource) do
      Puppet::Type.type(:network_iface).new(name: 'eth0', ensure: :present, provider: :nmcli)
    end

    let(:provider) { described_class.new(resource) }

    it 'is true when NetworkManager has a profile for it' do
      allow(described_class).to receive(:nmcli_connection_lookup)
        .and_return('NAME' => 'eth0', 'UUID' => 'b0ab376a', 'DEVICE' => 'eth0')
      allow(described_class).to receive(:nmcli_connection_show)
        .and_return('connection.id' => 'eth0', 'connection.interface-name' => 'eth0')

      expect(provider).to exist
    end

    it 'is false when it has none' do
      allow(described_class).to receive(:nmcli_connection_lookup).and_return(nil)

      expect(provider).not_to exist
    end

    # A profile bound to a MAC exists before the card is plugged in. Calling
    # that absent would recreate the profile on every run.
    it 'does not depend on the device being present' do
      allow(described_class).to receive(:nmcli_connection_lookup)
        .and_return('NAME' => 'eth0', 'UUID' => 'b0ab376a', 'DEVICE' => '')
      allow(described_class).to receive(:nmcli_connection_show)
        .and_return('connection.id' => 'eth0', '802-3-ethernet.mac-address' => '00:50:56:B9:1F:38')

      expect(provider).to exist
    end
  end

  describe '#create' do
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: 'eth0',
        ensure: :present,
        conn_name: 'System eth0',
        device: 'eth0',
        conn_type: 'Ethernet',
        bootproto: 'static',
        ipaddr: '216.251.35.10',
        prefix: 24,
        gateway: '216.251.35.1',
        onboot: true,
        provider: :nmcli,
      )
    end

    let(:provider) { described_class.new(resource) }

    # `connection add type ethernet` produces a profile reporting
    # 802-3-ethernet: the word that creates a connection is not the word that
    # reads one back.
    it 'creates the profile with the type nmcli takes, and its properties' do
      expect(described_class).to receive(:nmcli_connection_add).with(
        'type', 'ethernet',
        'con-name', 'System eth0',
        'ifname', 'eth0',
        'connection.autoconnect', 'yes',
        'ipv4.method', 'manual',
        'ipv4.addresses', '216.251.35.10/24',
        'ipv4.gateway', '216.251.35.1'
      )

      provider.create
    end

    it 'refuses a conn_type NetworkManager has no equivalent for' do
      expect { described_class.nmcli_add_type('Token Ring') }
        .to raise_error(Puppet::Error, %r{conn_type "Token Ring" has no NetworkManager equivalent})
    end
  end

  describe '#destroy' do
    before(:each) do
      allow(described_class).to receive(:nmcli_connection_lookup)
        .and_return('NAME' => 'eth0', 'UUID' => 'b0ab376a', 'DEVICE' => 'eth0')
      allow(described_class).to receive(:nmcli_connection_show)
        .and_return('connection.id' => 'eth0', 'connection.uuid' => 'b0ab376a')
    end

    # The parent deletes the link and nothing else, which fails on a physical
    # card and leaves the configuration behind on a virtual one. Absent means
    # the configuration is gone.
    it 'removes the profile and leaves a physical interface alone' do
      resource = Puppet::Type.type(:network_iface).new(name: 'eth0', ensure: :absent, provider: :nmcli)

      expect(described_class).to receive(:nmcli_connection_delete).with('b0ab376a')
      expect(described_class).not_to receive(:link_delete)

      described_class.new(resource).destroy
    end

    it 'also removes an interface the module created' do
      resource = Puppet::Type.type(:network_iface).new(
        name: 'o-hm0', ensure: :absent, link_kind: :veth, peer_name: 'o-bhm0', provider: :nmcli,
      )

      expect(described_class).to receive(:nmcli_connection_delete).with('b0ab376a')
      expect(described_class).to receive(:link_delete).with('o-hm0')

      described_class.new(resource).destroy
    end

    it 'says nothing to nmcli when there is no profile' do
      allow(described_class).to receive(:nmcli_connection_lookup).and_return(nil)
      resource = Puppet::Type.type(:network_iface).new(name: 'eth0', ensure: :absent, provider: :nmcli)

      expect(described_class).not_to receive(:nmcli_connection_delete)

      described_class.new(resource).destroy
    end
  end

  describe '#flush' do
    let(:resource) do
      Puppet::Type.type(:network_iface).new(
        name: 'eth0',
        ensure: :present,
        device: 'eth0',
        ipaddr: '216.251.35.10',
        prefix: 24,
        provider: :nmcli,
      )
    end

    let(:provider) { described_class.new(resource) }

    def profile(active)
      allow(described_class).to receive(:nmcli_connection_lookup)
        .and_return('NAME' => 'eth0', 'UUID' => 'b0ab376a', 'DEVICE' => 'eth0', 'ACTIVE' => active)
      allow(described_class).to receive(:nmcli_connection_show)
        .and_return('connection.id' => 'eth0', 'connection.uuid' => 'b0ab376a')
    end

    it 'does nothing when nothing changed' do
      profile('yes')
      expect(described_class).not_to receive(:nmcli_connection_modify)

      provider.flush
    end

    # Several of our properties are one of NetworkManager's between them, so
    # the whole declared state goes in one invocation rather than only what
    # changed, which would mean reassembling each composite by hand.
    it 'writes the declared state in one invocation, then applies it' do
      profile('yes')
      provider.ipaddr = '216.251.35.11'

      # onboot is not in the resource above and is written anyway: the type
      # defaults it to yes, and a default is as declared as anything else.
      expect(described_class).to receive(:nmcli_connection_modify)
        .with('b0ab376a',
              'connection.interface-name', 'eth0',
              'connection.autoconnect', 'yes',
              'ipv4.addresses', '216.251.35.10/24')
      expect(described_class).to receive(:nmcli_device_reapply).with('eth0')

      provider.flush
    end

    # The lo profile of web170c25 (Rocky 10.2, 2026-09-27) after loopbacks put
    # eight service addresses on it through network_alias. The interface owns
    # 127.0.0.1/8 and nothing else; a flush that wrote its own address alone
    # would erase the aliases and reapply would take them off the device.
    context 'on a loopback whose other addresses belong to network_alias' do
      let(:resource) do
        Puppet::Type.type(:network_iface).new(
          name: 'lo',
          ensure: :present,
          ipaddr: '127.0.0.1',
          netmask: '255.0.0.0',
          provider: :nmcli,
        )
      end

      let(:aliases) do
        '64.29.155.0/24, 69.49.112.0/24, 64.29.156.0/32, 209.235.157.0/24, ' \
          '209.235.144.12/32, 209.235.144.9/32, 69.49.118.0/24, 209.235.144.14/32'
      end

      before(:each) do
        allow(described_class).to receive(:nmcli_connection_lookup)
          .and_return('NAME' => 'lo', 'UUID' => '20be7eb0', 'DEVICE' => 'lo', 'ACTIVE' => 'yes')
        allow(described_class).to receive(:nmcli_connection_show)
          .and_return('connection.id' => 'lo', 'connection.uuid' => '20be7eb0',
                      'connection.type' => 'loopback', 'connection.interface-name' => 'lo',
                      'ipv4.method' => 'manual', 'ipv4.addresses' => "127.0.0.1/8, #{aliases}",
                      'ipv6.addresses' => '::1/128')
        allow(described_class).to receive(:nmcli_device_reapply)
      end

      it 'carries the undeclared secondaries over' do
        provider.onboot = 'no'

        expect(described_class).to receive(:nmcli_connection_modify)
          .with('20be7eb0', 'connection.autoconnect', 'yes',
                'ipv4.addresses', "127.0.0.1/8, #{aliases}")

        provider.flush
      end

      it 'writes the secondaries it declares, an empty list included' do
        resource[:ipaddr_secondaries] = []
        provider.onboot = 'no'

        expect(described_class).to receive(:nmcli_connection_modify)
          .with('20be7eb0', 'connection.autoconnect', 'yes', 'ipv4.addresses', '127.0.0.1/8')

        provider.flush
      end
    end

    # A profile nothing is running takes effect when it is next activated, and
    # asking NetworkManager to reapply it would fail for no reason.
    it 'does not apply a profile no device is running' do
      profile('no')
      provider.ipaddr = '216.251.35.11'

      allow(described_class).to receive(:nmcli_connection_modify)
      expect(described_class).not_to receive(:nmcli_device_reapply)

      provider.flush
    end

    # NetworkManager exits 6 for a change it cannot reapply. Reactivating would
    # apply it and take the interface down, so the resource fails instead and
    # says what applying it would cost.
    it 'fails, rather than reactivating, when the change cannot be applied' do
      profile('yes')
      provider.ipaddr = '216.251.35.11'

      allow(described_class).to receive(:nmcli_connection_modify)
      allow(described_class).to receive(:nmcli_device_reapply)
        .and_raise(Puppet::ExecutionFailure, "Can't reapply changes to '802-3-ethernet.s390-nettype' setting")

      expect { provider.flush }
        .to raise_error(Puppet::Error, %r{profile for eth0 was updated, but NetworkManager cannot apply it})
      expect { provider.flush }.to raise_error(Puppet::Error, %r{interrupts the interface})
    end
  end

  describe '#conn_type=' do
    let(:resource) do
      Puppet::Type.type(:network_iface).new(name: 'lo', ensure: :present, provider: :nmcli)
    end

    let(:provider) { described_class.new(resource) }

    before(:each) do
      allow(described_class).to receive(:nmcli_connection_lookup)
        .and_return('NAME' => 'lo', 'UUID' => '0d986ff8', 'DEVICE' => 'lo')
      allow(described_class).to receive(:nmcli_connection_show)
        .and_return('connection.id' => 'lo', 'connection.type' => 'loopback')
    end

    # A setter runs only where Puppet found the declared value different from
    # the current one, so this is exactly the case of asking NetworkManager to
    # change something it will not change.
    it 'refuses to change the type of a profile that exists' do
      expect { provider.conn_type = 'Ethernet' }
        .to raise_error(Puppet::Error, %r{cannot be changed from "loopback" to "Ethernet"})
    end

    it 'says what to do about it' do
      expect { provider.conn_type = 'Ethernet' }
        .to raise_error(Puppet::Error, %r{Remove conn_type from the resource})
    end
  end

  describe 'what it inherits' do
    it 'is a child of the ip provider' do
      expect(described_class.ancestors).to include(ip_provider)
    end

    it 'reaches the nmcli transport on the base class' do
      expect(described_class).to respond_to(:nmcli_connection_show, :nmcli_connection_modify)
    end

    it 'still reaches the ip transport it shares with its parent' do
      expect(described_class).to respond_to(:ip_caller, :link_show)
    end
  end
end
