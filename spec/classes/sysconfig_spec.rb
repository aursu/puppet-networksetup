# frozen_string_literal: true

require 'spec_helper'

describe 'networksetup::sysconfig' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      if os.match?(%r{^rocky-9})
        it {
          is_expected.not_to contain_file('/etc/sysconfig/network')
        }

        # skip all other tests
        next
      end

      context 'when default parameters' do
        let(:params) do
          {}
        end

        it {
          is_expected.to contain_file('/etc/sysconfig/network')
            .with_content(%r{^NETWORKING=yes})
        }

        it {
          is_expected.to contain_file('/etc/sysconfig/network')
            .with_content(%r{^NOZEROCONF=yes})
        }

        it {
          is_expected.to contain_file('/etc/sysconfig/network')
            .with_content(%r{^IPV6_AUTOCONF=no})
        }

        it {
          is_expected.to contain_file('/etc/sysconfig/network')
            .without_content(%r{^IPV6_DEFAULTGW=})
        }

        it {
          is_expected.to contain_file('/etc/sysconfig/network')
            .without_content(%r{^HOSTNAME=})
        }

        context 'and IPv6 gateway is set' do
          let(:params) { super().merge(ipv6_defaultgw: '2001:db8:1::242:ac11:2/64') }

          it {
            is_expected.to contain_file('/etc/sysconfig/network')
              .with_content(%r{^IPV6_DEFAULTGW="2001:db8:1::242:ac11:2/64"})
          }
        end

        context 'and hostname is set' do
          let(:params) { super().merge(hostname: 'hostname.intern.domain.tld') }

          it {
            is_expected.to contain_file('/etc/sysconfig/network')
              .with_content(%r{^HOSTNAME=hostname.intern.domain.tld})
          }

          context 'and hostname propagated from Puppet' do
            let(:facts) { os_facts.deep_merge('networking' => { 'fqdn' => 'hostname.domain.tld' }) }
            let(:params) { super().merge(puppet_propagate: true) }

            it {
              is_expected.to contain_file('/etc/sysconfig/network')
                .with_content(%r{^HOSTNAME=hostname.intern.domain.tld})
            }
          end
        end

        context 'and hostname propagated from Puppet' do
          let(:facts) { os_facts.deep_merge('networking' => { 'fqdn' => 'hostname.domain.tld' }) }
          let(:params) { super().merge(puppet_propagate: true) }

          it {
            is_expected.to contain_file('/etc/sysconfig/network')
              .with_content(%r{^HOSTNAME=hostname.domain.tld})
          }
        end
      end
    end
  end
end
