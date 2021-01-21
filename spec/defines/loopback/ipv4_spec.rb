# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::loopback::ipv4' do
  let(:title) { 'namevar' }
  let(:params) do
    {
      'addr' => '192.168.0.10',
    }
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      it {
        is_expected.to contain_network_alias('namevar')
          .with(
            parent_device: 'lo',
            ipaddr: '192.168.0.10',
          )
          .without_netmask
          .without_prefix
      }

      context 'when IP address with prefix' do
        let(:params) do
          {
            'addr' => '192.168.0.10/26',
          }
        end

        it {
          is_expected.to contain_network_alias('namevar')
            .with(
              parent_device: 'lo',
              ipaddr: '192.168.0.10',
              prefix: '26',
            )
            .without_netmask
        }

        context 'when prefix provided as well' do
          let(:params) { super().merge(prefix: 28) }

          it {
            is_expected.to contain_network_alias('namevar')
              .with(
                parent_device: 'lo',
                ipaddr: '192.168.0.10',
                prefix: 28,
              )
              .without_netmask
          }
        end
      end
    end
  end
end
