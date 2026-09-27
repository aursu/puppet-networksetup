# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::install' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      if os.start_with?('rocky-10')
        it 'installs NetworkManager where there are no network scripts' do
          is_expected.to contain_package('NetworkManager')
        end
      end
    end
  end

  # EL6 and EL7 are still running in the fleet - 79 nodes as of 2026-09-27 -
  # and dropping their support was not meant to install NetworkManager on
  # them. The release case must not sweep them into the branch for EL10.
  ['6', '7'].each do |major|
    describe "on a release older than the ones supported (EL#{major})" do
      let(:facts) do
        {
          'os' => { 'family' => 'RedHat', 'name' => 'CentOS', 'release' => { 'major' => major } },
          'networking' => { 'fqdn' => 'test.example.com' },
        }
      end

      it { is_expected.to compile }

      it 'installs nothing of its own' do
        is_expected.not_to contain_package('NetworkManager')
        is_expected.not_to contain_package('bridge-utils')
        is_expected.not_to contain_file('/etc/sysconfig/network-scripts')
      end
    end
  end
end
