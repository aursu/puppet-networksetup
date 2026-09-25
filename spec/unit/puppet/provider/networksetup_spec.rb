require 'spec_helper'
require 'puppet/provider/networksetup'

# Every sample below is real output of NetworkManager 1.56.0 on Rocky 10.2,
# shortened but not edited.
#
# The cop derives the expected filename from the class name and asks for
# network_setup_spec.rb. Every spec in this tree is named after the file it
# covers, and the file is networksetup.rb.
describe Puppet::Provider::NetworkSetup do # rubocop:disable RSpec/FilePath
  # nmcli --terse --fields all --mode multiline connection show lo
  let(:one_connection) do
    <<~OUT
      connection.id:lo
      connection.uuid:0d986ff8-b133-495e-b987-750a3d5fca89
      connection.type:loopback
      connection.interface-name:lo
      connection.zone:
      connection.metered:unknown
      connection.mptcp-flags:0x0
      ipv4.method:manual
      ipv4.addresses:127.0.0.1/8
      ipv4.gateway:
      ipv6.method:manual
      ipv6.addresses:::1/128
      ipv6.mtu:auto
      proxy.method:none
    OUT
  end

  # nmcli --terse --fields all --mode multiline connection show
  let(:all_connections) do
    <<~OUT
      NAME:cloud-init enp1s0
      UUID:a41601f3-3acc-5f60-ac5f-9d9011ab7c25
      TYPE:802-3-ethernet
      TIMESTAMP-REAL:Thu 03 Sep 2026 01:29:26 PM EDT
      DEVICE:enp1s0
      STATE:activated
      FILENAME:/etc/NetworkManager/system-connections/cloud-init-enp1s0.nmconnection
      NAME:lo
      UUID:0d986ff8-b133-495e-b987-750a3d5fca89
      TYPE:loopback
      TIMESTAMP-REAL:Thu 03 Sep 2026 01:29:26 PM EDT
      DEVICE:lo
      STATE:activated
      FILENAME:/run/NetworkManager/system-connections/lo.nmconnection
    OUT
  end

  # nmcli --terse --fields all --mode multiline connection show, on a host
  # carrying two profiles named eth0: the active one generated under /run and
  # an inactive one saved under /etc.
  let(:colliding_names) do
    <<~OUT
      NAME:eth0
      UUID:b0ab376a-2bbd-4d82-a430-3f673ad44c15
      TYPE:802-3-ethernet
      ACTIVE:yes
      DEVICE:eth0
      STATE:activated
      FILENAME:/run/NetworkManager/system-connections/eth0.nmconnection
      NAME:eth0
      UUID:9300d121-6af9-4db1-aca7-408bf3844cea
      TYPE:802-3-ethernet
      ACTIVE:no
      DEVICE:
      STATE:
      FILENAME:/etc/NetworkManager/system-connections/eth0.nmconnection
      NAME:System eth1
      UUID:9c92fad9-6ecb-3e6c-eb4d-8a47c6f50c04
      TYPE:802-3-ethernet
      ACTIVE:yes
      DEVICE:eth1
      STATE:activated
      FILENAME:/etc/sysconfig/network-scripts/ifcfg-eth1
    OUT
  end

  describe '.nmcli_caller' do
    before(:each) do
      allow(described_class).to receive(:nmcli_comm).and_return('/usr/bin/nmcli')
    end

    it 'calls nmcli through the shared system caller' do
      expect(described_class).to receive(:system_caller)
        .with('/usr/bin/nmcli', 'connection', 'show')
        .and_return('connection.id:lo')

      expect(described_class.nmcli_caller('connection', 'show')).to eq('connection.id:lo')
    end
  end

  describe '.nmcli_parse_records' do
    it 'returns an empty array for no output' do
      expect(described_class.nmcli_parse_records(nil)).to eq([])
      expect(described_class.nmcli_parse_records('')).to eq([])
    end

    it 'starts a new record where the field names begin again' do
      records = described_class.nmcli_parse_records(all_connections)

      expect(records.length).to eq(2)
      expect(records[0]['NAME']).to eq('cloud-init enp1s0')
      expect(records[0]['DEVICE']).to eq('enp1s0')
      expect(records[1]['NAME']).to eq('lo')
      expect(records[1]['FILENAME']).to eq('/run/NetworkManager/system-connections/lo.nmconnection')
    end

    it 'gives one record for one connection' do
      expect(described_class.nmcli_parse_records(one_connection).length).to eq(1)
    end

    it 'keeps a value that is itself full of colons' do
      records = described_class.nmcli_parse_records(one_connection)

      expect(records[0]['ipv6.addresses']).to eq('::1/128')
      expect(records[0]['ipv4.addresses']).to eq('127.0.0.1/8')
    end

    it 'takes a value verbatim, escaping nothing' do
      records = described_class.nmcli_parse_records(all_connections)

      expect(records[0]['TIMESTAMP-REAL']).to eq('Thu 03 Sep 2026 01:29:26 PM EDT')
      expect(records[0]['NAME']).to eq('cloud-init enp1s0')
    end

    it 'keeps an unset property as an empty string' do
      records = described_class.nmcli_parse_records(one_connection)

      expect(records[0]['connection.zone']).to eq('')
      expect(records[0]['ipv4.gateway']).to eq('')
    end

    it 'ignores a line with no separator at all' do
      expect(described_class.nmcli_parse_records("lo\nipv4.method:manual\n"))
        .to eq([{ 'ipv4.method' => 'manual' }])
    end
  end

  describe '.nmcli_parse' do
    it 'returns an empty hash for no output' do
      expect(described_class.nmcli_parse(nil)).to eq({})
      expect(described_class.nmcli_parse('')).to eq({})
    end

    it 'returns the properties of the one connection shown' do
      desc = described_class.nmcli_parse(one_connection)

      expect(desc['connection.id']).to eq('lo')
      expect(desc['connection.type']).to eq('loopback')
      expect(desc['ipv4.method']).to eq('manual')
      expect(desc['ipv6.addresses']).to eq('::1/128')
    end
  end

  describe '.nmcli_connection_list' do
    it 'reads every connection in one call' do
      expect(described_class).to receive(:nmcli_caller)
        .with('--terse', '--fields', 'all', '--mode', 'multiline', 'connection', 'show')
        .and_return(all_connections)

      expect(described_class.nmcli_connection_list.map { |c| c['NAME'] })
        .to eq(['cloud-init enp1s0', 'lo'])
    end

    it 'returns an empty array when nmcli says nothing' do
      allow(described_class).to receive(:nmcli_caller).and_return(nil)

      expect(described_class.nmcli_connection_list).to eq([])
    end
  end

  describe '.nmcli_connection_lookup' do
    before(:each) do
      allow(described_class).to receive(:nmcli_caller).and_return(all_connections)
    end

    it 'finds a connection by its profile name' do
      expect(described_class.nmcli_connection_lookup('cloud-init enp1s0')['DEVICE']).to eq('enp1s0')
    end

    it 'falls back to the device a connection is bound to' do
      expect(described_class.nmcli_connection_lookup('eth0', 'enp1s0')['NAME']).to eq('cloud-init enp1s0')
    end

    it 'prefers the name over the device' do
      expect(described_class.nmcli_connection_lookup('lo', 'enp1s0')['NAME']).to eq('lo')
    end

    context 'when two profiles carry the same name' do
      before(:each) do
        allow(described_class).to receive(:nmcli_caller).and_return(colliding_names)
      end

      it 'returns the active one' do
        expect(described_class.nmcli_connection_lookup('eth0')['UUID'])
          .to eq('b0ab376a-2bbd-4d82-a430-3f673ad44c15')
      end

      it 'finds by device only among the profiles that have one' do
        expect(described_class.nmcli_connection_lookup('nosuch', 'eth1')['NAME']).to eq('System eth1')
      end
    end

    it 'returns nil when neither matches' do
      expect(described_class.nmcli_connection_lookup('eth0', 'eth0')).to be_nil
    end

    it 'does not look by device when none was given' do
      expect(described_class.nmcli_connection_lookup('eth0')).to be_nil
      expect(described_class.nmcli_connection_lookup('eth0', '')).to be_nil
    end
  end

  describe '.nmcli_writer' do
    before(:each) do
      allow(described_class).to receive(:nmcli_comm).and_return('nmcli')
      allow(Puppet::Util).to receive(:which).with('nmcli').and_return('/usr/bin/nmcli')
    end

    # `nmcli connection modify nmtest ipv4.gateway ''` clears the gateway,
    # which is the only way to unset a property. The shared system_caller
    # drops empty arguments, so writes cannot go through it.
    it 'keeps an empty value, which is how a property is unset' do
      expect(Puppet::Util::Execution).to receive(:execute)
        .with("/usr/bin/nmcli connection modify nmtest ipv4.gateway ''")
        .and_return('')

      described_class.nmcli_writer('connection', 'modify', 'nmtest', 'ipv4.gateway', '')
    end

    # nmcli exits 2 on an unknown property and 10 on an unknown connection,
    # while a successful modify prints nothing - so a swallowed failure would
    # be indistinguishable from success.
    it 'lets a failed command fail the run' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .and_raise(Puppet::ExecutionFailure, "Error: unknown connection 'nosuchconn'.")

      expect { described_class.nmcli_writer('connection', 'modify', 'nosuchconn', 'connection.zone', 'x') }
        .to raise_error(Puppet::ExecutionFailure, %r{unknown connection})
    end

    it 'fails when nmcli is not installed' do
      allow(Puppet::Util).to receive(:which).with('nmcli').and_return(nil)

      expect { described_class.nmcli_writer('connection', 'show') }
        .to raise_error(Puppet::Error, %r{nmcli command not found})
    end
  end

  describe 'the writing helpers' do
    it 'adds a connection' do
      expect(described_class).to receive(:nmcli_writer)
        .with('connection', 'add', 'type', 'loopback', 'con-name', 'lo')

      described_class.nmcli_connection_add('type', 'loopback', 'con-name', 'lo')
    end

    it 'modifies a connection by id' do
      expect(described_class).to receive(:nmcli_writer)
        .with('connection', 'modify', 'lo', 'ipv4.addresses', '127.0.0.1/8')

      described_class.nmcli_connection_modify('lo', 'ipv4.addresses', '127.0.0.1/8')
    end

    it 'deletes a connection by id' do
      expect(described_class).to receive(:nmcli_writer).with('connection', 'delete', 'lo')

      described_class.nmcli_connection_delete('lo')
    end

    it 'brings a connection up by id' do
      expect(described_class).to receive(:nmcli_writer).with('connection', 'up', 'lo')

      described_class.nmcli_connection_up('lo')
    end
  end

  describe '.nmcli_connection_show' do
    it 'reads every property of one connection' do
      expect(described_class).to receive(:nmcli_caller)
        .with('--terse', '--fields', 'all', '--mode', 'multiline', 'connection', 'show', 'lo')
        .and_return(one_connection)

      expect(described_class.nmcli_connection_show('lo')['connection.uuid'])
        .to eq('0d986ff8-b133-495e-b987-750a3d5fca89')
    end

    it 'returns an empty hash for a connection nmcli does not know' do
      allow(described_class).to receive(:nmcli_caller).and_return(nil)

      expect(described_class.nmcli_connection_show('nosuch')).to eq({})
    end
  end
end
