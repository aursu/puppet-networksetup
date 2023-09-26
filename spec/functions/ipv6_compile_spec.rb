require 'spec_helper'

describe 'networksetup::ipv6_compile' do
  context 'with default settings' do
    it {
      is_expected.to run.with_params('fe80::dea6:32ff', '10.100.16.7').and_return('fe80::dea6:32ff:0a64:1007/64')
    }

    it {
      is_expected.to run.with_params('fe80::dea6:', '10.100.16.7').and_return(nil)
    }
  end
end
