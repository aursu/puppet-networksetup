require 'spec_helper'

describe 'networksetup::gateway_prediction' do
  context 'with only address' do
    it {
      is_expected.to run.with_params('192.168.10.30').and_return('192.168.10.1')
    }

    it {
      is_expected.to run.with_params('192.168.10.30/28').and_return('192.168.10.17')
    }
  end
end