# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::params' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }
    end
  end

  # The default arm of the release case used to mean "10 and everything else",
  # so a release that still has ifcfg files would have been swept into the
  # NetworkManager branch and its files silently changed. The observable
  # difference is what networksetup::loopback declares.
  describe 'a release older than the ones this module supports' do
    let(:pre_condition) { 'include networksetup::loopback' }
    let(:facts) do
      {
        'os' => { 'family' => 'RedHat', 'name' => 'CentOS', 'release' => { 'major' => '7' } },
        'networking' => { 'fqdn' => 'test.example.com' },
      }
    end

    it 'keeps the ifcfg keys rather than being treated as NetworkManager' do
      is_expected.to contain_network_iface('lo')
        .with_conn_type('Ethernet')
        .with_network('127.0.0.0')
        .with_conn_name('loopback')
    end
  end

  describe 'a release newer than the ones named' do
    let(:pre_condition) { 'include networksetup::loopback' }
    let(:facts) do
      {
        'os' => { 'family' => 'RedHat', 'name' => 'Rocky', 'release' => { 'major' => '11' } },
        'networking' => { 'fqdn' => 'test.example.com' },
      }
    end

    it 'is NetworkManager, like EL10' do
      is_expected.to contain_network_iface('lo').without_conn_type
    end
  end
end
