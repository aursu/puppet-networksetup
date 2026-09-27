require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_alias).provide(
  :nmcli,
  parent: :ip,
) do
  desc 'Keep an additional address on the parent interface NetworkManager profile.

    An alias is not an object in NetworkManager. ifcfg gave each one a file and
    a label - lo:myspc - and the label was the alias. A NetworkManager profile
    has one address list per family and no label anywhere in it, so an alias
    here is one entry of the parent connection list and nothing more.

    That the list is shared is why this provider adds and removes single
    entries rather than writing the property whole. A resource that owns one
    element of a property cannot write the property.'

  initvars

  commands ip: 'ip', nmcli: 'nmcli'

  confine osfamily: :redhat
  defaultfor osfamily: :redhat, operatingsystemmajrelease: ['10']

  mk_resource_methods

  def initialize(value = {})
    super(value)
    @connection = nil
  end

  # The profile of the parent interface. An alias never has one of its own.
  def connection
    return @connection if @connection

    @listed = self.class.nmcli_connection_lookup(parent_device, parent_device)
    @connection = @listed ? self.class.nmcli_connection_show(@listed['UUID']) : {}
  end

  def parent_device
    @resource[:parent_device] || @resource[:device].to_s.split(':').first
  end

  def address_family
    @resource[:ipv6addr] ? 'ipv6' : 'ipv4'
  end

  # The address this resource owns, as NetworkManager spells it. An entry is
  # removed by its exact address/prefix: `-ipv4.addresses 10.0.0.1` without the
  # prefix exits 0 and removes nothing, so a guess here would be a silent
  # failure rather than an error.
  def address
    declared = @resource[:ipv6addr] || @resource[:ipaddr]
    return nil if declared.nil?

    addr, prefix = declared.to_s.split('/')
    prefix ||= @resource[:ipv6_prefixlength] || @resource[:prefix]
    prefix ||= @resource[:netmask] && IPAddr.new("#{addr}/#{@resource[:netmask]}").prefix
    prefix ||= (address_family == 'ipv6') ? 128 : 32

    "#{addr}/#{prefix}"
  end

  # The entry as the profile currently carries it, which is where a prefix
  # comes from when the resource did not give one.
  def current_address
    addr = address.to_s.split('/').first
    return nil if addr.empty?

    self.class.address_list(connection["#{address_family}.addresses"])
        .find { |entry| entry.split('/').first == addr }
  end

  def exists?
    !current_address.nil?
  end

  def create
    if connection.empty?
      raise Puppet::Error,
            _("NetworkManager has no profile for #{parent_device}, so there is nothing to add " \
              "#{address} to. Declare a network_iface for #{parent_device}, or create its profile.")
    end

    self.class.nmcli_connection_modify(connection['connection.uuid'], "+#{address_family}.addresses", address)
    apply
  end

  # Removing an address that is not there exits 0 and does nothing, so this
  # needs no guard - but it does need the prefix the profile actually carries,
  # which may differ from the one the resource declares.
  def destroy
    return if connection.empty?

    self.class.nmcli_connection_modify(connection['connection.uuid'], "-#{address_family}.addresses", current_address || address)
    apply
  end

  # Only a prefix can change in place. The address cannot: an alias has no
  # identity in a NetworkManager profile beyond the address itself - the label
  # that used to be its name has nowhere to live - so nothing connects this
  # resource to the entry it had before. Puppet sees the declared address
  # missing, calls create, and the old entry stays until something declares it
  # absent. That is a property of the model, not of this code.
  #
  # Where the address is unchanged the entry is found, and it is replaced in
  # one invocation so the interface is never briefly without either.
  def flush
    return if @property_flush.empty?

    # a label that drifted needs no profile change, only putting back
    if @property_flush.keys == [:device]
      apply_label
      @property_hash.merge!(@property_flush)
      @property_flush.clear
      return
    end

    self.class.nmcli_connection_modify(
      connection['connection.uuid'],
      "-#{address_family}.addresses", current_address,
      "+#{address_family}.addresses", address
    )

    apply

    @property_hash.merge!(@property_flush)
    @property_flush.clear
  end

  # ip a shows an alias as lo:myspc, and that label was the whole of what an
  # alias was. A NetworkManager profile has nowhere to keep it, so the label is
  # live kernel state: the profile carries the address, the label goes on
  # afterwards, and it is gone again after every reactivation until a Puppet
  # run puts it back. Reporting it truthfully is what makes that run notice.
  def live_label
    local = address.to_s.split('/').first
    info = self.class.addr_lookup(local)
    return nil if info.empty?

    info['ifa_label'] || parent_device
  end

  # Measured on NetworkManager 1.56.0 and the kernel under it: an address put
  # on the device with `ip addr add ... label` keeps its label through
  # `nmcli device reapply`,
  # and loses it when the connection is fully reactivated, which re-adds every
  # address without one. So the label is applied before the reapply, while the
  # address is not yet on the device - afterwards it would be EEXIST - and
  # restored by a later run when a reactivation has taken it away.
  #
  # Whether the kernel took it is checked rather than assumed. A label that
  # silently did not stick is drift nobody would see.
  def apply_label
    wanted = @resource[:device]
    return if wanted.nil? || wanted == parent_device

    local = address.to_s.split('/').first
    info = self.class.addr_lookup(local)

    if info.empty?
      self.class.addr_create(address, 'dev', parent_device, 'label', wanted)
    elsif info['ifa_label'] != wanted
      # `ip addr change <addr> dev <dev> label <label>` exits 0 and changes
      # nothing - measured - so the entry is replaced instead. The address is
      # absent for the moment between the two calls, which happens only after
      # a reactivation has stripped the label, and therefore only on a device
      # that has just come up.
      self.class.addr_delete(address, parent_device)
      self.class.addr_create(address, 'dev', parent_device, 'label', wanted)
    else
      return
    end

    return if self.class.addr_label(local) == wanted

    raise Puppet::Error,
          _("the kernel did not take the label \"#{wanted}\" for #{address} on #{parent_device}. " \
            'NetworkManager does not store labels, so this one is applied with ip, and it is lost ' \
            'whenever the connection is reactivated.')
  end

  def apply
    return unless @listed && @listed['ACTIVE'] == 'yes'

    # the label goes on first: NetworkManager leaves an address that is already
    # there, and putting it on afterwards would be EEXIST
    apply_label
    self.class.nmcli_device_reapply(parent_device)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error,
          _("the profile for #{parent_device} was updated, but NetworkManager cannot apply it to the " \
            'running device: ' + e.message.to_s.strip + '. It takes effect when the connection is ' \
            'reactivated, which interrupts the interface.')
  end

  # Only the address is an alias. TYPE, ONBOOT, BOOTPROTO and the rest were
  # keys of the alias ifcfg file and belong to the parent connection here, so
  # this provider reports the address and says nothing about the others rather
  # than reporting the parent's values as if they were its own.
  def ifcfg_data
    @addrinfo ||= begin
      entry = current_address.to_s.split('/')

      if address_family == 'ipv6'
        { 'device' => live_label, 'parent_device' => parent_device,
          'ipv6addr' => entry[0], 'ipv6_prefixlength' => entry[1] }.compact
      else
        { 'device' => live_label, 'parent_device' => parent_device,
          'ipaddr' => entry[0], 'prefix' => entry[1],
          'netmask' => entry[1] && IPAddr.new('255.255.255.255').mask(entry[1].to_i).to_s }.compact
      end
    end
  end
end
