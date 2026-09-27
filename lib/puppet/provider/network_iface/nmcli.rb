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

    @listed = self.class.nmcli_connection_lookup(name, device_name)
    @connection = @listed ? self.class.nmcli_connection_show(@listed['UUID']) : {}
  end

  def device_name
    @resource[:device] || interface_name || @resource[:name]
  end

  # Whether a device is running this profile right now. Only then is there
  # anything to apply: a profile nothing is using takes effect when it is next
  # activated, and asking NetworkManager to reapply it would fail for no
  # reason.
  def active?
    connection
    @listed && @listed['ACTIVE'] == 'yes'
  end

  # The one method the whole read path hangs from: every property getter the
  # base class defines is `ifcfg_data[attr]`, so replacing the persistence
  # layer is replacing this. The parent reads and parses an ifcfg file; here
  # the same hash comes out of a NetworkManager profile.
  # ifcfg_data carries these as a space-separated string, the shape
  # IPV6ADDR_SECONDARIES had, and the type wants an array - the same split the
  # parent does for the IPv6 list.
  def ipaddr_secondaries
    ifcfg_data['ipaddr_secondaries']&.split&.map(&:strip)
  end

  def ifcfg_data
    @addrinfo ||= self.class.nmcli_properties(
      connection,
      'ipaddr' => @resource[:ipaddr],
      'ipv6addr' => @resource[:ipv6addr],
    )
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
  # The resource's own properties, which is what a profile is created from.
  # A parameter the manifest did not give is not a value to write: nmcli
  # leaves a property it is not told about at NetworkManager's default, which
  # is what an undeclared property means.
  # MANAGED_PROPERTIES is the union across the four types, so it is filtered by
  # what this resource's own type has - asking a network_iface for arpcheck,
  # which belongs to network_alias, raises rather than returning nil.
  def declared_properties
    self.class::MANAGED_PROPERTIES.each_with_object({}) do |attr, props|
      next unless @resource.class.validattr?(attr)

      value = @resource[attr]
      next if value.nil?

      props[attr.to_s] = value
    end
  end

  def create
    return super if @resource[:link_kind] == :veth

    # con-name and ifname are how `connection add` says these two, so they are
    # not repeated as connection.id and connection.interface-name.
    rest = declared_properties.reject { |attr, _| ['conn_name', 'device'].include?(attr) }

    self.class.nmcli_connection_add(
      'type', self.class.nmcli_add_type(@resource[:conn_type]),
      'con-name', @resource[:conn_name] || @resource[:name],
      'ifname', @resource[:device] || interface_name || @resource[:name],
      *self.class.nmcli_arguments(rest)
    )
  end

  # absent means the configuration is gone, which is meaningful for every
  # interface. The parent deletes the link and nothing else, so on a physical
  # card it fails and on a virtual one it leaves the configuration behind.
  #
  # Here the profile always goes, and the interface itself only where the
  # module made it - a declared link_kind says so. A physical card is left
  # alone, and nothing has to know at compile time which kind it is, which a
  # master could not tell anyway.
  #
  # Deleting the profile of an active connection takes the interface down with
  # it. That is what was asked for, but it is worth knowing before asking.
  def destroy
    self.class.nmcli_connection_delete(connection['connection.uuid']) unless connection.empty?
    self.class.link_delete(@resource[:name]) if @resource[:link_kind]
  end

  # One `connection modify` carries every declared property, not only the ones
  # Puppet found changed. Several properties of ours are one of
  # NetworkManager's between them - an address and its prefix, an IPv6 primary
  # and its secondaries - so writing only what changed would mean reassembling
  # each composite from a mixture of new and current values. Writing the
  # declared state whole is one command, idempotent, and needs no such
  # arithmetic.
  def flush
    return if @property_flush.empty?

    self.class.nmcli_connection_modify(
      connection['connection.uuid'],
      *self.class.nmcli_arguments(declared_properties),
    )

    apply

    @property_hash.merge!(@property_flush)
    @property_flush.clear
  end

  # Writing a profile does not change the device running it. reapply does,
  # without interrupting it - but not for every property. Where NetworkManager
  # refuses, the profile is already correct and only the running device is
  # behind, so the resource fails rather than reactivating the connection
  # itself: that would take the interface down, and on the interface Puppet is
  # talking over, the run would take its own connection with it.
  def apply
    return unless active?

    begin
      self.class.nmcli_device_reapply(device_name)
    rescue Puppet::ExecutionFailure => e
      raise Puppet::Error,
            _("the profile for #{device_name} was updated, but NetworkManager cannot apply it to the " \
              'running device: ' + e.message.to_s.strip + '. It takes effect when the connection is ' \
              "reactivated - `nmcli connection up #{@resource[:conn_name] || @resource[:name]}` - which " \
              'interrupts the interface.')
    end
  end

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
