require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_route).provide(:nmcli, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network routes using NetworkManager nmcli.'

  confine osfamily: :redhat
  defaultfor osfamily: :redhat, operatingsystemmajrelease: ['10']

  commands ip: 'ip', nmcli: 'nmcli'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  # --- nmcli helpers ---

  def self.nmcli_caller(*args)
    system_caller(command(:nmcli), *args)
  end

  def self.nmcli_connection_list
    output = nmcli_caller('--terse', '--fields', 'NAME,UUID,TYPE,DEVICE', 'connection', 'show')
    return [] unless output

    connections = []
    output.each_line do |line|
      line = line.strip
      next if line.empty?
      parts = line.split(':', 4)
      next unless parts.size >= 4
      connections << {
        'name'   => parts[0],
        'uuid'   => parts[1],
        'type'   => parts[2],
        'device' => parts[3],
      }
    end
    connections
  end

  def self.nmcli_connection_show(conn_id)
    output = nmcli_caller('--terse', '--fields', 'all', 'connection', 'show', conn_id)
    return {} unless output

    data = {}
    output.each_line do |line|
      line = line.strip
      next if line.empty?
      key, value = line.split(':', 2)
      next unless key && value
      data[key.strip.downcase] = value.strip
    end
    data
  end

  def self.find_connection_by_device(device)
    connections = nmcli_connection_list
    conn = connections.find { |c| c['device'] == device }
    conn || connections.find { |c| c['name'] == device }
  end

  # Get routes for a specific NM connection
  # Returns array of route hashes from ipv4.routes field
  def self.nmcli_get_routes(conn_id)
    data = nmcli_connection_show(conn_id)
    routes = []

    # ipv4.routes field format: "{ dst = X, nh = Y, mt = Z }; ..."
    route_str = data['ipv4.routes']
    if route_str && route_str != '--' && !route_str.empty?
      route_str.split(';').each do |r|
        r = r.strip
        next if r.empty?
        route = {}
        # Parse "{ dst = 10.0.0.0/8, nh = 192.168.1.1, mt = 100 }" or "dst/prefix via gw"
        if r =~ /dst\s*=\s*([^,}]+)/
          route['dst'] = Regexp.last_match(1).strip
        end
        if r =~ /nh\s*=\s*([^,}]+)/
          nh = Regexp.last_match(1).strip
          route['gateway'] = nh unless nh == '0.0.0.0' || nh.empty?
        end
        routes << route unless route.empty?
      end
    end

    routes
  end

  # --- instances/prefetch for route discovery ---

  def self.command_to_hash(info)
    hash = {}

    hash[:ensure] = :present
    hash[:destination] = info['dst']
    hash[:gateway] = info['gateway']
    hash[:device] = info['dev']

    hash[:name] = hash[:destination].to_s +
                  (hash[:gateway] ? " via #{hash[:gateway]}" : '') +
                  (hash[:device] ? " dev #{hash[:device]}" : '')
    hash[:provider] = name

    hash
  end

  def self.instances
    return @instances if @instances
    @instances = []

    begin
      routeinfo_show.each do |routeinfo|
        hash = command_to_hash(routeinfo)
        @instances << new(hash) unless hash.empty?
      end
    rescue Puppet::ExecutionFailure => e
      raise Puppet::Error, _("Failed to list routes #{e.message}"), e.backtrace
    end

    @instances
  end

  def self.prefetch(resources)
    instances.each do |provider|
      resource = resources[provider.name]
      if resource
        resource.provider = provider
        resource[:ensure] = :present
      else
        resources.each_value do |resource|
          next unless resource[:destination] == provider.destination

          device = resource[:device] || get_device_by_network(resource[:lookup_device])&.first
          next unless device == provider.device

          next if provider.gateway && resource[:gateway] != provider.gateway

          resource.provider = provider
          resource[:ensure] = :present
        end
      end
    end
  end

  def self.route_lookup(dst, device, gateway)
    routeinfo = routeinfo_show
    return {} unless routeinfo.is_a?(Array)

    routeinfo = routeinfo.select { |info| info['dst'] == dst }
    routeinfo = routeinfo.select { |info| info['dev'] == device } if device
    routeinfo = routeinfo.select { |info| info['gateway'] == gateway } if gateway

    routeinfo.first || {}
  end

  def route_lookup
    return {} unless resource

    dst = resource[:destination]
    device = resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gateway = resource[:gateway]

    self.class.route_lookup(dst, device, gateway)
  end

  # --- Property getters ---

  def exists?
    @property_hash[:ensure] == :present
  end

  def destination
    @destination ||= @property_hash[:destination] || route_lookup['dst']
  end

  def gateway
    @gateway ||= @property_hash[:gateway] || route_lookup['gateway']
  end

  def device
    @device ||= @property_hash[:device] || route_lookup['device']
  end

  def destination=(value)
    @property_flush[:destination] = value
  end

  def gateway=(value)
    @property_flush[:gateway] = value
  end

  def device=(value)
    @property_flush[:device] = value
  end

  # --- NM route persistence ---

  def self.add_route_to_nm(dev, dst, gateway = nil)
    return unless dev && !dev.empty?

    conn = find_connection_by_device(dev)
    return unless conn

    conn_id = conn['uuid'] || conn['name']
    route_spec = dst.to_s
    route_spec += " #{gateway}" if gateway && !gateway.empty?

    nmcli_caller('connection', 'modify', conn_id, '+ipv4.routes', route_spec)
  end

  def self.remove_route_from_nm(dev, dst, gateway = nil)
    return unless dev && !dev.empty?

    conn = find_connection_by_device(dev)
    return unless conn

    conn_id = conn['uuid'] || conn['name']
    route_spec = dst.to_s
    route_spec += " #{gateway}" if gateway && !gateway.empty?

    nmcli_caller('connection', 'modify', conn_id, '-ipv4.routes', route_spec)
  end

  # --- CRUD ---

  def destroy
    return if route_lookup.empty?

    dst = resource[:destination]
    dev = resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gw  = resource[:gateway]

    Puppet.debug "Deleting route: dst=#{dst}, dev=#{dev}, gateway=#{gw}"
    self.class.route_delete(dst, dev, gw)
    self.class.remove_route_from_nm(dev, dst, gw)
  end

  def create
    dst     = resource[:destination]
    dev     = resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gw      = resource[:gateway]
    nocreate = resource[:nocreate]

    Puppet.debug "Creating route: dst=#{dst}, dev=#{dev}, gateway=#{gw}"
    self.class.route_create(dst, dev, gw)
    self.class.add_route_to_nm(dev, dst, gw) unless nocreate
  end

  def flush
    return if @property_flush.empty?

    dst     = resource[:destination]
    dev     = @property_flush[:device] || resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gw      = @property_flush[:gateway] || resource[:gateway]
    nocreate = resource[:nocreate]

    Puppet.debug "Flushing route changes: dst=#{dst}, dev=#{dev}, gateway=#{gw}"

    if @property_hash[:ensure] == :present
      old_dev = @property_hash[:device]
      old_gw  = @property_hash[:gateway]
      self.class.route_delete(dst, old_dev, old_gw)
      self.class.remove_route_from_nm(old_dev, dst, old_gw)
    end

    self.class.route_create(dst, dev, gw)
    self.class.add_route_to_nm(dev, dst, gw) unless nocreate

    @property_hash.merge!(@property_flush)
    @property_flush.clear
  end
end
