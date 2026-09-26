require 'spec_helper'
require 'puppet/provider/network_iface/nmcli'

describe Puppet::Type.type(:network_iface).provider(:nmcli) do
  let(:ip_provider) { Puppet::Type.type(:network_iface).provider(:ip) }

  # Which provider a release resolves to is the one thing that has to be proven
  # rather than reasoned about: an interface managed by the wrong one writes its
  # configuration where nothing reads it and reports success.
  #
  # It is proven through `default?` and `specificity` rather than through
  # `defaultprovider`, because `commands` adds an implicit "this binary exists"
  # confine and the test image carries neither `ip` nor `nmcli` — there, every
  # provider is unsuitable and `defaultprovider` is nil whatever the facts say.
  describe 'provider selection' do
    def with_release(major)
      facter = Puppet.runtime[:facter]
      allow(facter).to receive(:value).and_call_original
      allow(facter).to receive(:value).with(:osfamily).and_return('RedHat')
      allow(facter).to receive(:value).with(:operatingsystemmajrelease).and_return(major)
      yield
    end

    it 'is a default on EL10, which has no network-scripts' do
      with_release('10') do
        expect(described_class).to be_default
      end
    end

    it 'is not a default on EL9' do
      with_release('9') do
        expect(described_class).not_to be_default
      end
    end

    it 'is not a default on EL8' do
      with_release('8') do
        expect(described_class).not_to be_default
      end
    end

    it 'leaves EL8 and EL9 to the ip provider' do
      with_release('9') { expect(ip_provider).to be_default }
      with_release('8') { expect(ip_provider).to be_default }
    end

    # On EL10 both providers are defaults - the ip one claims the whole RedHat
    # family - so the winner is the more specific, and that has to stay true.
    it 'outranks the ip provider where both apply' do
      with_release('10') do
        expect(described_class).to be_default
        expect(ip_provider).to be_default
      end

      expect(described_class.specificity).to be > ip_provider.specificity
    end
  end

  describe 'what it inherits' do
    it 'is a child of the ip provider' do
      expect(described_class.ancestors).to include(ip_provider)
    end

    it 'reaches the nmcli transport on the base class' do
      expect(described_class).to respond_to(:nmcli_connection_show, :nmcli_connection_modify)
    end

    it 'still reaches the ip transport it shares with its parent' do
      expect(described_class).to respond_to(:ip_caller, :link_show)
    end
  end
end
