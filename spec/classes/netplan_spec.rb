# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::netplan' do
  # Two ethernets bonded with 802.3ad, a VLAN on top of the bond carrying the
  # addresses, the resolvers and the default route. This is the full feature
  # set the class renders today.
  let(:bonded_vlan_host) do
    {
      'ethernets' => {
        'eno1'   => { 'dhcp4' => false },
        'eno2'   => { 'dhcp4' => true },
        'ens3f0' => { 'dhcp4' => false },
        'ens3f1' => { 'dhcp4' => false },
      },
      'bonds' => {
        'bond0' => {
          'interfaces' => ['ens3f0', 'ens3f1'],
          'dhcp4'      => false,
          'parameters' => {
            'mode'                 => '802.3ad',
            'lacp-rate'            => 'fast',
            'mii-monitor-interval' => 100,
          },
        },
      },
      'vlans' => {
        'eth0' => {
          'id'          => 316,
          'link'        => 'bond0',
          'addresses'   => ['192.0.2.11/26', '192.0.2.31/26'],
          'nameservers' => { 'addresses' => ['198.51.100.55', '198.51.100.20'] },
          'routes'      => [{ 'to' => 'default', 'via' => '192.0.2.1' }],
        },
      },
    }
  end

  let(:bonded_vlan_config) do
    <<~CONFIG
      network:
        version: 2
        ethernets:
          eno1:
            dhcp4: false
          eno2:
            dhcp4: true
          ens3f0:
            dhcp4: false
          ens3f1:
            dhcp4: false
        bonds:
          bond0:
            interfaces:
              - ens3f0
              - ens3f1
            dhcp4: false
            parameters:
              mode: 802.3ad
              lacp-rate: fast
              mii-monitor-interval: 100
        vlans:
          eth0:
            id: 316
            link: bond0
            addresses:
              - 192.0.2.11/26
              - 192.0.2.31/26
            nameservers:
              addresses:
                - 198.51.100.55
                - 198.51.100.20
            routes:
              - to: default
                via: 192.0.2.1
    CONFIG
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      unless os.match?(%r{^ubuntu-})
        context 'when the operating system is not Debian based' do
          let(:params) { bonded_vlan_host }

          it {
            is_expected.to compile.and_raise_error(%r{supported on Debian based systems only})
          }
        end

        # skip all other tests
        next
      end

      context 'when no device is defined' do
        it {
          is_expected.to compile.and_raise_error(%r{needs at least one of ethernets, bonds or vlans})
        }
      end

      context 'when a bond, a VLAN and resolvers are defined' do
        let(:params) { bonded_vlan_host }

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_file('/etc/netplan/00-installer-config.yaml')
            .with_ensure('file')
            .with_owner('root')
            .with_group('root')
            .with_mode('0600')
        }

        # The managed-by header is asserted separately so that rewording it does
        # not require the whole configuration to be restated.
        it {
          is_expected.to contain_file('/etc/netplan/00-installer-config.yaml')
            .with_content(%r{\A# THIS FILE IS MANAGED BY PUPPET\n})
        }

        it {
          content = catalogue.resource('file', '/etc/netplan/00-installer-config.yaml')[:content]
          expect(content[content.index("network:\n")..-1]).to eq(bonded_vlan_config)
        }

        it {
          is_expected.to contain_exec('netplan generate')
            .with_command('/usr/sbin/netplan generate')
            .with_refreshonly(true)
            .that_subscribes_to('File[/etc/netplan/00-installer-config.yaml]')
        }

        it {
          is_expected.to contain_exec('netplan apply')
            .with_command('/usr/sbin/netplan apply')
            .with_refreshonly(true)
            .that_subscribes_to('File[/etc/netplan/00-installer-config.yaml]')
        }

        # netplan generate only rewrites /run, so it must validate the file
        # before netplan apply touches the running interfaces.
        it {
          is_expected.to contain_exec('netplan generate')
            .that_comes_before('Exec[netplan apply]')
        }
      end

      context 'when apply is disabled' do
        let(:params) { bonded_vlan_host.merge('apply' => false) }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_exec('netplan generate') }
        it { is_expected.not_to contain_exec('netplan apply') }
      end

      context 'when generate is disabled' do
        let(:params) { bonded_vlan_host.merge('generate' => false) }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_exec('netplan generate') }
        it { is_expected.to contain_exec('netplan apply') }
      end

      context 'when a renderer and a custom path are given' do
        let(:params) do
          bonded_vlan_host.merge(
            'renderer'    => 'NetworkManager',
            'config'      => '/etc/netplan/50-puppet.yaml',
            'config_mode' => '0640',
          )
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_file('/etc/netplan/50-puppet.yaml')
            .with_mode('0640')
            .with_content(%r{^  renderer: NetworkManager$})
        }
      end

      context 'when an ethernet carries an address, an MTU, search domains and a route metric' do
        let(:params) do
          {
            'ethernets' => {
              'eno1' => {
                'addresses'   => ['192.0.2.10/24'],
                'mtu'         => 9000,
                'nameservers' => {
                  'search'    => ['example.com'],
                  'addresses' => ['198.51.100.55'],
                },
                'routes' => [
                  { 'to' => '203.0.113.0/24', 'via' => '192.0.2.1', 'metric' => 100 },
                ],
              },
            },
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_file('/etc/netplan/00-installer-config.yaml')
            .with_content(%r{^      mtu: 9000$})
            .with_content(%r{^        search:\n          - example\.com$})
            .with_content(%r{^        - to: 203\.0\.113\.0/24\n          via: 192\.0\.2\.1\n          metric: 100$})
        }
      end

      context 'when an address is given without a prefix' do
        let(:params) do
          { 'ethernets' => { 'eno1' => { 'addresses' => ['192.0.2.10'] } } }
        end

        it { is_expected.to compile.and_raise_error(%r{parameter 'ethernets'}) }
      end

      context 'when a bond has no members' do
        let(:params) do
          { 'bonds' => { 'bond0' => { 'dhcp4' => false } } }
        end

        it { is_expected.to compile.and_raise_error(%r{parameter 'bonds'}) }
      end

      context 'when a VLAN id is out of range' do
        let(:params) do
          { 'vlans' => { 'eth0' => { 'id' => 4095, 'link' => 'bond0' } } }
        end

        it { is_expected.to compile.and_raise_error(%r{parameter 'vlans'}) }
      end
    end
  end
end
