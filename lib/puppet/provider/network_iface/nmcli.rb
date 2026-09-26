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

  def initialize(value = {})
    super(value)
    @connection = nil
  end

  # The profile this resource is about, or an empty hash when NetworkManager
  # has never heard of it. Looked up by connection name, then by device, the
  # way the ip provider looks for an ifcfg file under either name.
  #
  # hwaddr is the third way in, and it is the one that matters operationally:
  # a resource can say only "the interface whose MAC is X" - which is all that
  # is known from a hypervisor's control panel - and never name an interface
  # or a connection. The MAC resolves to a device through /sys, and the device
  # to a connection, which is the same chain the ip provider walks.
  def connection
    return @connection if @connection

    name = @resource[:conn_name] || @resource[:name]
    device = @resource[:device] || interface_name || @resource[:name]

    found = self.class.nmcli_connection_lookup(name, device)
    @connection = found ? self.class.nmcli_connection_show(found['UUID']) : {}
  end

  # The one method the whole read path hangs from: every property getter the
  # base class defines is `ifcfg_data[attr]`, so replacing the persistence
  # layer is replacing this. The parent reads and parses an ifcfg file; here
  # the same hash comes out of a NetworkManager profile.
  def ifcfg_data
    @addrinfo ||= self.class.nmcli_properties(connection)
  end

  # For the parent this asks about two things at once - an interface exists and
  # it has an ifcfg script - because ifcfg kept the configuration beside the
  # device but not attached to it. NetworkManager has one object, the profile,
  # and it can perfectly well exist for a device that is not present: a profile
  # bound to a MAC waits for the card. That is not absent, it is inactive, and
  # a provider that called it absent would recreate the profile on every run.
  #
  # veth stays with the parent. NetworkManager has no model for a pair of
  # interfaces created together, so those are made with ip and are real as soon
  # as the link is.
  # connection.type is fixed when a profile is created and NetworkManager will
  # not change it afterwards. A setter runs only where Puppet found the
  # declared value different from the current one, so reaching here means the
  # manifest is asking for something no provider can do, and saying so is more
  # use than attempting it. Declaring the type a profile already has costs
  # nothing - no setter runs - and creating a profile uses it normally.
  def conn_type=(value)
    raise Puppet::Error,
          _("connection type cannot be changed from \"#{conn_type}\" to \"#{value}\": NetworkManager fixes it " \
            'when the profile is created. Remove conn_type from the resource. Changing it means replacing the ' \
            'profile, which takes the interface down with it.')
  end

  def exists?
    return super if @resource[:link_kind] == :veth

    !connection.empty?
  end
end
