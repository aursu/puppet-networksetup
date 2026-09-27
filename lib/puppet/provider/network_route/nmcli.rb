require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_route).provide(
  :nmcli,
  parent: :ip,
) do
  desc 'Keep a route in the NetworkManager profile of the interface it leaves by.

    A route is not an object in NetworkManager either. It is either the
    connection gateway or an entry of its route list, and which of the two
    depends on the destination:

      destination => default        ipv4.gateway, one per connection
      destination => 10.0.0.0/24    an entry of ipv4.routes

    So the default route is written whole, since the connection owns it, and
    any other route is added to and taken from the list, since the resource
    owns one entry of it. That is the same division the addresses of
    network_iface and network_alias fall on, and the same one a future
    provider of ipv4.routing-rules would.'

  initvars

  commands ip: 'ip', nmcli: 'nmcli'

  confine osfamily: :redhat
  defaultfor osfamily: :redhat, operatingsystemmajrelease: ['10']

  mk_resource_methods

  # The parent reads the kernel routing table: its instances come from
  # `ip route show` and its prefetch marks a resource present when the kernel
  # has the route, which is right for a provider that manages the live table.
  # This one manages what is stored, and a route the kernel has from DHCP is
  # not in any profile - taking it for one would mean never writing it.
  def self.instances
    []
  end

  def self.prefetch(_resources); end

  def initialize(value = {})
    super(value)
    @connection = nil
  end

  def device_name
    @resource[:device] || self.class.get_device_by_network(@resource[:lookup_device])&.first
  end

  def connection
    return @connection if @connection

    @listed = self.class.nmcli_connection_lookup(device_name, device_name)
    @connection = @listed ? self.class.nmcli_connection_show(@listed['UUID']) : {}
  end

  def default_route?
    @resource[:destination].to_s == 'default'
  end

  def address_family
    @resource[:destination].to_s.include?(':') ? 'ipv6' : 'ipv4'
  end

  def routes_property
    "#{address_family}.routes"
  end

  def gateway_property
    "#{address_family}.gateway"
  end

  # The entry as this resource would write it: destination, next hop, metric,
  # which is the order NetworkManager stores and prints them in.
  def entry
    [@resource[:destination], @resource[:gateway], @resource[:metric]].compact.join(' ')
  end

  # The entry as the profile carries it, matched on the destination, since
  # that is the part a resource can be sure of. Removal needs this rather than
  # `entry`: `-ipv4.routes` matches the whole string, and one stored with a
  # metric is not removed by a destination and gateway alone.
  def current_entry
    self.class.nmcli_list_entries(connection, routes_property)
        .find { |route| route.split.first == @resource[:destination].to_s }
  end

  def exists?
    return false if connection.empty?
    return !connection[gateway_property].to_s.empty? if default_route?

    !current_entry.nil?
  end

  def create
    if connection.empty?
      raise Puppet::Error,
            _("NetworkManager has no profile for #{device_name}, so there is nowhere to put the route " \
              "\"#{entry}\". Declare a network_iface for #{device_name}, or create its profile.")
    end

    if default_route?
      self.class.nmcli_connection_modify(connection['connection.uuid'], gateway_property, @resource[:gateway].to_s)
    else
      self.class.nmcli_list_add(connection['connection.uuid'], routes_property, entry)
    end

    apply
  end

  def destroy
    return if connection.empty?

    if default_route?
      self.class.nmcli_connection_modify(connection['connection.uuid'], gateway_property, '')
    else
      self.class.nmcli_list_remove(connection['connection.uuid'], routes_property, current_entry || entry)
    end

    apply
  end

  def flush
    return if @property_flush.empty?

    if default_route?
      self.class.nmcli_connection_modify(connection['connection.uuid'], gateway_property, @resource[:gateway].to_s)
    else
      self.class.nmcli_connection_modify(
        connection['connection.uuid'],
        "-#{routes_property}", current_entry,
        "+#{routes_property}", entry
      )
    end

    apply

    @property_hash.merge!(@property_flush)
    @property_flush.clear
  end

  def apply
    return unless @listed && @listed['ACTIVE'] == 'yes'

    self.class.nmcli_device_reapply(device_name)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error,
          _("the profile for #{device_name} was updated, but NetworkManager cannot apply it to the " \
            'running device: ' + e.message.to_s.strip + '. It takes effect when the connection is ' \
            'reactivated, which interrupts the interface.')
  end

  # The parent answers these from the kernel too. Here they come from the
  # profile, which is what this provider manages.
  def destination
    ifcfg_data['destination']
  end

  def gateway
    ifcfg_data['gateway']
  end

  def device
    ifcfg_data['device']
  end

  def metric
    ifcfg_data['metric']
  end

  # The route as it is stored, named the way the type names it. A default
  # route has no entry in the list - it is the connection gateway - so it is
  # read from there.
  def ifcfg_data
    @addrinfo ||= if default_route?
                    { 'destination' => 'default', 'device' => device_name,
                      'gateway' => nilify(connection[gateway_property]) }.compact
                  else
                    destination, gateway, metric = current_entry.to_s.split
                    { 'destination' => destination, 'gateway' => gateway, 'metric' => metric,
                      'device' => device_name }.compact
                  end
  end

  def nilify(value)
    (value.nil? || value.empty?) ? nil : value
  end
end
