require 'spec_helper'
require 'ipaddr'

provider_class = Puppet::Type.type(:network_alias).provider(:ip)
describe provider_class do
  describe 'check path to config' do
    let(:resource_name) { 'lo:osdev' }
    let(:resource) do
      Puppet::Type.type(:network_alias).new(
        name: resource_name,
        ipaddr: '127.0.0.5',
        ensure: :present,
        provider: :ip,
      )
    end
    let(:provider) do
      provider = subject
      provider.resource = resource
      provider
    end

    it {
      expect(provider.config_path).to eq('/etc/sysconfig/network-scripts/ifcfg-lo:osdev')
    }
  end
end
