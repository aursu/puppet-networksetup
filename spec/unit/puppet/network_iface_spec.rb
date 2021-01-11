require 'spec_helper'

describe Puppet::Type.type(:network_iface) do
  context 'check resource validation' do
    it do
      expect {
        described_class.new(
          name: 'o-bhm0',
          type: :veth,
          ensure: :present,
        )
      }.to raise_error(Puppet::Error, %r{error: peer name property must be specified for VETH tunnel})
    end
  end
end
