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

    hash[:name] = hash[:destination] + (hash[:gateway] ? " via #{hash[:gateway]}" : '') + (hash[:device] ? " dev #{hash[:device]}" : '')
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
    dst = resource[:destination]
    device = resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
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

  def self.route_config_file(dev)
    "/etc/sysconfig/network-scripts/route-#{dev}"
  end

  def self.write_route_config(dev, dst, gateway = nil)
    return unless dev && !dev.empty?

    config_file = route_config_file(dev)

    # Создаем файл, если его нет
    if File.exist?(config_file)
      # Проверяем, есть ли уже такая запись
      existing_routes = File.readlines(config_file).map(&:strip)
    else
      Puppet.debug "Creating route config file: #{config_file}"
      File.open(config_file, 'w') { |f| f.write("# Created by Puppet\n") }
      existing_routes = []
    end

    new_route = gateway ? "#{dst} via #{gateway}" : dst.to_s
    return if existing_routes.include?(new_route) # Избегаем дубликатов

    Puppet.debug "Adding route to #{config_file}: #{new_route}"
    File.open(config_file, 'a') { |f| f.puts(new_route) }
  end

  def self.remove_route_from_config(dev, dst)
    return unless dev && !dev.empty?

    config_file = route_config_file(dev)
    return unless File.exist?(config_file)

    Puppet.debug "Removing route #{dst} from #{config_file}"

    new_content = File.readlines(config_file).reject { |line| line.strip.start_with?(dst) }

    if new_content.empty?
      Puppet.debug "No more routes left, deleting #{config_file}"
      File.delete(config_file)
    else
      File.open(config_file, 'w') { |f| f.write(new_content.join("\n")) }
    end
  end

  def destroy
    return if route_lookup.empty?

    dst = resource[:destination]
    dev = resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gateway = resource[:gateway]

    Puppet.debug "Deleting route: dst=#{dst}, dev=#{dev}, gateway=#{gateway}"
    self.class.route_delete(dst, dev, gateway)
    self.class.remove_route_from_config(dev, dst) # Удаляем из конфига
  end

  def create
    dst = resource[:destination]
    dev = resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gateway = resource[:gateway]
    nocreate = resource[:nocreate]

    Puppet.debug "Creating route: dst=#{dst}, dev=#{dev}, gateway=#{gateway}"
    self.class.route_create(dst, dev, gateway)
    self.class.write_route_config(dev, dst, gateway) unless nocreate
  end

  def flush
    return if @property_flush.empty? # Если нечего менять, просто выходим

    dst = resource[:destination]
    dev = @property_flush[:device] || resource[:device] || self.class.get_device_by_network(resource[:lookup_device])&.first
    gateway = @property_flush[:gateway] || resource[:gateway]
    nocreate = resource[:nocreate]

    Puppet.debug "Flushing route changes: dst=#{dst}, dev=#{dev}, gateway=#{gateway}"

    if @property_hash[:ensure] == :present
      old_dev = @property_hash[:device]
      old_gateway = @property_hash[:gateway]
      self.class.route_delete(dst, old_dev, old_gateway)
      self.class.remove_route_from_config(old_dev, dst) # Удаляем старую запись
    end

    self.class.route_create(dst, dev, gateway)
    self.class.write_route_config(dev, dst, gateway) unless nocreate

    @property_hash.merge!(@property_flush)
    @property_flush.clear
  end
end
