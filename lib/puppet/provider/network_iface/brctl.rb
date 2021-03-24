require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_iface).provide(
  :brctl,
  :parent => :ip, # rubocop:disable Style/HashSyntax
) do
  desc 'Manage network interfaces and bridge settings.'

  initvars

  commands ip: 'ip', brctl: 'brctl'
  confine osfamily: :redhat, operatingsystemmajrelease: ['6', '7']

  mk_resource_methods

  def self.brctl_comm
    command(:brctl)
  end

  def brctl_caller(*args)
    self.class.system_caller(brctl_comm, *args)
  end

  def bridge=(brname)
    name = @resource[:name]
    if linkinfo_show['slave-kind'] == 'bridge_slave'
      if brname == :absent
        brctl_caller('delif', brname, name)
      else
        raise Puppet::Error, _("device #{name} is already a member of a bridge") unless linkinfo_show['master'] == brname
      end
    else
      # eg brctl addif brqfc32e1e1-6f o-bhm0
      brctl_caller('addif', brname, name)
    end
    @property_flush[:bridge] = brname
  end

  def ipv6addr_secondaries
    ifcfg_data['ipv6addr_secondaries'].split.map { |a| a.strip } if ifcfg_data['ipv6addr_secondaries']
  end

  def ipv6_prefixlength
    ipv6addr.split('/')[1] if ipv6addr
  end
end
