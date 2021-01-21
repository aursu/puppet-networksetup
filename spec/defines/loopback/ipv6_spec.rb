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

      it { is_expected.to compile }
    end
  end
end
