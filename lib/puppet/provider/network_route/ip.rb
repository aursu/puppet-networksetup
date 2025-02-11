require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_route).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network route.'

  commands ip: 'ip'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.command_to_hash(info)
    hash = {}

    hash[:ensure] = :present
    hash[:destination] = info['dst']
    hash[:gateway] = info['gateway']
    hash[:device] = info['dev']

    hash[:name] = hash[:destination] + (hash[:gateway] ? " via #{hash[:gateway]}" : "") + (hash[:device] ? " dev #{hash[:device]}" : "")
    hash[:provider] = name

    hash
  end

  def self.instances
    return @instances if @instances
    @instances = []

    # list out all of the packages
    begin
      routeinfo_show.each do |routeinfo|
          # now turn each returned line into a package object
          hash = command_to_hash(routeinfo)
          @instances << new(hash) unless hash.empty?
      end
    rescue Puppet::ExecutionFailure => e
      raise Puppet::Error, _("Failed to list routes #{e.message}"), e.backtrace
    end

    @instances
  end


  def self.prefetch(resources)
    # is there a better way to do this? Map network_route to the provider regardless of the title
    # and make sure all system resources have ensure => :present so that we don't try to remove them
    instances.each do |provider|
      resource = resources[provider.name]
      if resource
        resource.provider = provider
        resource[:ensure] = :present
      else
        resources.each_value do |resource|
          next unless resource[:destination] == provider.destination

          device = resource[:device] || get_device_by_network(resource[:lookup_network])&.first
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
    dst = resource[:destination]
    device = resource[:device] || self.class.get_device_by_network(resource[:lookup_network])&.first
    gateway = resource[:gateway]

    self.class.route_lookup(dst, device, gateway)
  end

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

  def destroy
    return if route_lookup.empty?

    dst = resource[:destination]
    dev = resource[:device] || self.class.get_device_by_network(resource[:lookup_network])&.first
    gateway = resource[:gateway]

    Puppet.debug "Deleting route: dst=#{dst}, dev=#{dev}, gateway=#{gateway}"
    self.class.route_delete(dst, dev, gateway)
  end

  def create
    dst = resource[:destination]
    dev = resource[:device] || self.class.get_device_by_network(resource[:lookup_network])&.first
    gateway = resource[:gateway]

    Puppet.debug "Creating route: dst=#{dst}, dev=#{dev}, gateway=#{gateway}"
    self.class.route_create(dst, dev, gateway)
  end


  def flush
    return if @property_flush.empty?  # Если нечего менять, просто выходим

    dst = resource[:destination]
    dev = @property_flush[:device] || resource[:device] || self.class.get_device_by_network(resource[:lookup_network])&.first
    gateway = @property_flush[:gateway] || resource[:gateway]

    Puppet.debug "Flushing route changes: dst=#{dst}, dev=#{dev}, gateway=#{gateway}"

    if @property_hash[:ensure] == :present
      old_dev = @property_hash[:device]
      old_gateway = @property_hash[:gateway]
      self.class.route_delete(dst, old_dev, old_gateway)
    end

    self.class.route_create(dst, dev, gateway)

    # Сбрасываем @property_flush, обновляем @property_hash
    @property_hash.merge!(@property_flush)
    @property_flush.clear
  end
end
