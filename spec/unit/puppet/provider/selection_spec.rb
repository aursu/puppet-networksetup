require 'spec_helper'
require 'puppet/provider/network_iface/nmcli'
require 'puppet/provider/network_alias/nmcli'
require 'puppet/provider/network_route/nmcli'

# Which provider each release resolves to, for every type that has an nmcli
# provider. A type whose ip provider is not a default anywhere does not fall
# back to it: with no default suitable, Puppet takes the most specific suitable
# provider, and nmcli is installed on EL8 and EL9 too. That is how network_alias
# reached a NetworkManager profile on EL9 while its address was in an ifcfg
# file - measured on a websiteos node, `provider_used: nmcli`.
#
# Proven through `default?` and `specificity` rather than `defaultprovider`,
# for the reason given in network_iface/nmcli_spec.rb: the test image has
# neither binary, so every provider is unsuitable there.
describe 'provider selection' do
  def with_release(major)
    facter = Puppet.runtime[:facter]
    allow(facter).to receive(:value).and_call_original
    allow(facter).to receive(:value).with(:osfamily).and_return('RedHat')
    allow(facter).to receive(:value).with(:operatingsystemmajrelease).and_return(major)
    yield
  end

  [:network_iface, :network_alias, :network_route].each do |type|
    context type.to_s do
      let(:ip_provider) { Puppet::Type.type(type).provider(:ip) }
      let(:nmcli_provider) { Puppet::Type.type(type).provider(:nmcli) }

      ['8', '9'].each do |major|
        it "is left to the ip provider on EL#{major}" do
          with_release(major) do
            expect(ip_provider).to be_default
            expect(nmcli_provider).not_to be_default
          end
        end
      end

      it 'goes to the nmcli provider on EL10, the more specific of two defaults' do
        with_release('10') do
          expect(ip_provider).to be_default
          expect(nmcli_provider).to be_default
        end

        expect(nmcli_provider.specificity).to be > ip_provider.specificity
      end
    end
  end
end
