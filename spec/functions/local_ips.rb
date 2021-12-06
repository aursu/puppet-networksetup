require 'spec_helper'

net_fact = {
  networking: {
    'fqdn' => 'k8s1-lv-lw-eu.host.cryengine.com',
    'mac' => '48:df:37:ca:a9:64',
    'netmask' => '255.255.255.192',
    'ip' => '192.168.218.176',
    'mtu' => 1500,
    'domain' => 'host.cryengine.com',
    'hostname' => 'k8s1-lv-lw-eu',
    'interfaces': {
      'lo': {
        'bindings': [
          {
            'address' => '127.0.0.1',
            'netmask' => '255.0.0.0',
            'network' => '127.0.0.0',
          },
        ],
        'mtu' => 65536,
        'ip' => '127.0.0.1',
        'netmask' => '255.0.0.0',
        'network' => '127.0.0.0',
      },
      'eno5' => {
        'mac' => '48:df:37:ca:a9:64',
        'bindings': [
          {
            'address' => '192.168.218.176',
            'netmask' => '255.255.255.192',
            'network' => '192.168.218.128',
          },
        ],
        'mtu' => 1500,
        'ip' => '192.168.218.176',
        'netmask' => '255.255.255.192',
        'network' => '192.168.218.128',
      },
      'eno6': {
        'mac' => '48:df:37:ca:a9:65',
        'bindings' => [
          {
            'address' => '10.154.4.12',
            'netmask' => '255.255.254.0',
            'network' => '10.154.4.0',
          },
          {
            'address' => '10.153.1.86',
            'netmask' => '255.255.252.0',
            'network' => '10.153.0.0',
          },
        ],
        'mtu' => 9000,
        'ip' => '10.154.4.12',
        'netmask' => '255.255.254.0',
        'network' => '10.154.4.0',
      },
      'eno7': {
        'mac' => '48:df:37:ca:a9:66',
        'mtu' => 1500,
      },
      'eno8': {
        'mac' => '48:df:37:ca:a9:67',
        'mtu' => 1500,
      }
    },
    'primary' => 'eno5',
    'network' => '192.168.218.128',
  }
}

describe 'networksetup::local_ips' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts.merge(net_fact) }

      context 'with no parameters' do
        it {
          is_expected.to run.and_return(['192.168.218.176', '127.0.0.1', '10.154.4.12', '10.153.1.86'])
        }
      end

      context 'with net parameter' do
        it {
          is_expected.to run.with_params('10.154.4.0/24').and_return(['10.154.4.12'])
        }
      end

      context 'with wrong parameter' do
        it {
          is_expected.to run.with_params('10.300.4.0/24').and_raise_error(%r{expects a Stdlib::IP::Address})
        }
      end

      context 'with undef parameter' do
        it {
          is_expected.to run.with_params(nil).and_return(['192.168.218.176', '127.0.0.1', '10.154.4.12', '10.153.1.86'])
        }
      end

      context 'with broad network' do
        it {
          is_expected.to run.with_params('10.152.0.0/14').and_return(['10.154.4.12', '10.153.1.86'])
        }
      end

      context 'with unknown network' do
        it {
          is_expected.to run.with_params('10.10.0.0/16').and_return([])
        }
      end
    end
  end
end
