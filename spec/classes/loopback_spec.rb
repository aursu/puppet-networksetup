# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::loopback' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      # TYPE=Ethernet for a loopback interface was what initscripts wanted.
      # NetworkManager has a real type for it and will not change one after
      # the profile exists, so the fiction is declared only where an ifcfg
      # file is what gets written.
      if os.start_with?('rocky-10')
        it 'does not declare a connection type it cannot set' do
          is_expected.to contain_network_iface('lo').without_conn_type
        end

        # NetworkManager derives both from the address and stores neither, so
        # a resource declaring them would be out of sync on every run.
        it 'does not declare what NetworkManager derives' do
          is_expected.to contain_network_iface('lo').without_network
          is_expected.to contain_network_iface('lo').without_broadcast
        end
      else
        it 'keeps declaring TYPE=Ethernet where an ifcfg file is written' do
          is_expected.to contain_network_iface('lo').with_conn_type('Ethernet')
        end

        it 'keeps declaring the ifcfg keys byte for byte' do
          is_expected.to contain_network_iface('lo')
            .with_network('127.0.0.0')
            .with_broadcast('127.255.255.255')
        end
      end
    end
  end
end
