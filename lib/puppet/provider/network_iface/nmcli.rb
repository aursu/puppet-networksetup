require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_iface).provide(
  :nmcli,
  parent: :ip,
) do
  desc 'Persist a network interface as a NetworkManager connection profile.

    The state of the interface is still read and changed with ip, exactly as
    the parent provider does. Only persistence differs: where the parent writes
    an ifcfg file, this one keeps a NetworkManager profile, which is the only
    mechanism releases without network-scripts have.'

  initvars

  commands ip: 'ip', nmcli: 'nmcli'

  confine osfamily: :redhat
  defaultfor osfamily: :redhat, operatingsystemmajrelease: ['10']

  mk_resource_methods
end
