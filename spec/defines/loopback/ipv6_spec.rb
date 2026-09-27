# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::loopback::ipv6' do
  let(:title) { 'namevar6' }
  let(:params) do
    {
      'addr' => '2001:db8:1::242:ac11:2/64',
    }
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      # The ifcfg based network_alias and network_iface types are RedHat
      # only; Ubuntu support is declared for networksetup::netplan alone.
      next if os.match?(%r{^ubuntu})

      it { is_expected.to compile }

      # TYPE was a key of the alias ifcfg file. In a NetworkManager profile it
      # belongs to the parent connection, so an alias declaring it would be
      # asking for a change no provider can make.
      if os.start_with?('rocky-10')
        it 'does not declare a connection type it does not own' do
          is_expected.to contain_network_alias('namevar6').without_conn_type
        end
      else
        it 'keeps declaring TYPE=Ethernet where an ifcfg file is written' do
          is_expected.to contain_network_alias('namevar6').with_conn_type('Ethernet')
        end
      end
    end
  end
end
