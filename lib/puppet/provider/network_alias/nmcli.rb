require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))
require 'ipaddr'

Puppet::Type.type(:network_alias).provide(:nmcli, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network aliases using NetworkManager nmcli.'

  confine osfamily: :redhat
  defaultfor osfamily: :redhat, operatingsystemmajrelease: ['10']

  commands ip: 'ip', nmcli: 'nmcli'

  def initialize(value = {})
    super(value)
    @property_flush = {}
    @connection_data = nil
  end

  # --- nmcli helpers ---

  def self.nmcli_caller(*args)
    system_caller(command(:nmcli), *args)
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

  def self.find_connection(device_name)
    connections = nmcli_connection_list
    conn = connections.find { |c| c['name'] == device_name }
    conn || connections.find { |c| c['device'] == device_name }
  end

  # --- Connection data ---

  def connection_info
    device = @resource[:device]
    @conn_info ||= self.class.find_connection(device)
  end

  def connection_data
    return @connection_data if @connection_data

    info = connection_info
    return {} unless info

    @connection_data = self.class.nmcli_connection_show(info['uuid'])
  end

  # --- mk_resource_methods equivalent ---

  def device
    connection_data['connection.interface-name']
  end

  def parent_device
    dev = device
    dev&.split(':')&.first
  end

  def conn_type
    nm_type = connection_data['connection.type']
    case nm_type
    when '802-3-ethernet', 'ethernet'
      'Ethernet'
    when 'bridge'
      'Bridge'
    else
      nm_type
    end
  end

  def ipaddr
    addrs = connection_data['ipv4.addresses']
    return nil unless addrs && !addrs.empty? && addrs != '--'
    first = addrs.split(',').first&.strip
    first&.split('/')&.first
  end

  def prefix
    addrs = connection_data['ipv4.addresses']
    return nil unless addrs && !addrs.empty? && addrs != '--'
    first = addrs.split(',').first&.strip
    first&.split('/')&.last&.to_i
  end

  def netmask
    p = prefix
    return nil unless p
    IPAddr.new('255.255.255.255').mask(p.to_i).to_s
  end

  def ipv6init
    method = connection_data['ipv6.method']
    (method && method != 'disabled' && method != 'ignore') ? 'yes' : 'no'
  end

  def ipv6addr
    addrs = connection_data['ipv6.addresses']
    return nil unless addrs && !addrs.empty? && addrs != '--'
    first = addrs.split(',').first&.strip
    first
  end

  def ipv6_prefixlength
    addr = ipv6addr
    addr&.split('/')&.last
  end

  def ipv6_defaultgw
    val = connection_data['ipv6.gateway']
    (val && val != '--') ? val : nil
  end

  def ipv6addr_secondaries
    addrs = connection_data['ipv6.addresses']
    return nil unless addrs && !addrs.empty? && addrs != '--'

    parts = addrs.split(',').map(&:strip)
    return nil if parts.size <= 1
    parts[1..-1]
  end

  # Unused fields that mk_resource_methods might call
  %w[bootproto broadcast conn_name defroute dns gateway
     hwaddr ipv6_autoconf ipv6_defroute master
     network nm_controlled onboot slave uuid arpcheck].each do |attr|
    define_method(attr) { nil }
    define_method("#{attr}=") { |val| @property_flush[attr.to_sym] = val }
  end

  # --- CRUD ---

  def exists?
    # For aliases managed via nmcli, we check if the parent connection has this alias address
    # The alias concept maps to additional addresses on the parent connection
    res_ipaddr = @resource[:ipaddr]
    res_ipv6addr = @resource[:ipv6addr]

    if res_ipaddr
      # Check if address exists on parent device via ip addr
      addr_info = self.class.addr_lookup(res_ipaddr)
      return addr_info['local'] == res_ipaddr
    end

    if res_ipv6addr
      addr_v6 = res_ipv6addr.split('/').first
      addr_info = self.class.addr_lookup(addr_v6)
      return addr_info['local'] == addr_v6
    end

    false
  end

  def create
    parent_dev = @resource[:parent_device]
    alias_name = @resource[:name]
    device_name = @resource[:device] || [parent_dev, alias_name].join(':')

    res_ipaddr = @resource[:ipaddr]
    res_prefix = @resource[:prefix]
    res_netmask = @resource[:netmask]
    res_ipv6init = @resource[:ipv6init]
    res_ipv6addr = @resource[:ipv6addr]
    res_ipv6_prefixlength = @resource[:ipv6_prefixlength]
    res_ipv6addr_secondaries = @resource[:ipv6addr_secondaries]
    res_ipv6_defaultgw = @resource[:ipv6_defaultgw]

    if res_ipaddr
      pfx = res_prefix
      unless pfx
        pfx = self.class.netmask_prefix(res_netmask) if res_netmask
      end
      pfx ||= 32

      addr_with_prefix = "#{res_ipaddr}/#{pfx}"

      # Add address using ip addr add with label for alias compatibility
      args = [addr_with_prefix, 'brd', '+', 'dev', parent_dev]
      args += ['scope', 'host'] if parent_dev == 'lo'
      args += ['label', device_name] if device_name

      self.class.addr_create(*args)

      # Also add to NM connection for persistence
      conn_info = self.class.find_connection(parent_dev)
      if conn_info
        conn_id = conn_info['uuid'] || conn_info['name']
        self.class.nmcli_caller('connection', 'modify', conn_id, '+ipv4.addresses', addr_with_prefix)
      end
    end

    if res_ipv6init == 'yes' && res_ipv6addr
      addr_v6 = res_ipv6addr
      if res_ipv6_prefixlength && !addr_v6.include?('/')
        addr_v6 = "#{addr_v6}/#{res_ipv6_prefixlength}"
      elsif !addr_v6.include?('/')
        addr_v6 = "#{addr_v6}/64"
      end

      args = [addr_v6, 'dev', parent_dev]
      self.class.addr_create(*args)

      # Also add secondary addresses
      if res_ipv6addr_secondaries
        [res_ipv6addr_secondaries].flatten.each do |sec_addr|
          self.class.addr_create(sec_addr, 'dev', parent_dev)
        end
      end

      # Persist in NM
      conn_info = self.class.find_connection(parent_dev)
      if conn_info
        conn_id = conn_info['uuid'] || conn_info['name']
        self.class.nmcli_caller('connection', 'modify', conn_id, '+ipv6.addresses', addr_v6)

        if res_ipv6addr_secondaries
          [res_ipv6addr_secondaries].flatten.each do |sec_addr|
            self.class.nmcli_caller('connection', 'modify', conn_id, '+ipv6.addresses', sec_addr)
          end
        end

        if res_ipv6_defaultgw
          self.class.nmcli_caller('connection', 'modify', conn_id, 'ipv6.gateway', res_ipv6_defaultgw)
        end
      end
    end
  end

  def destroy
    parent_dev = @resource[:parent_device]
    res_ipaddr = @resource[:ipaddr]
    res_ipv6addr = @resource[:ipv6addr]

    if res_ipaddr
      self.class.addr_delete(res_ipaddr, parent_dev)

      # Remove from NM connection
      conn_info = self.class.find_connection(parent_dev)
      if conn_info
        pfx = @resource[:prefix] || 32
        conn_id = conn_info['uuid'] || conn_info['name']
        self.class.nmcli_caller('connection', 'modify', conn_id, '-ipv4.addresses', "#{res_ipaddr}/#{pfx}")
      end
    end

    if res_ipv6addr
      addr_v6 = res_ipv6addr.split('/').first
      self.class.addr_delete(addr_v6, parent_dev)

      conn_info = self.class.find_connection(parent_dev)
      if conn_info
        conn_id = conn_info['uuid'] || conn_info['name']
        self.class.nmcli_caller('connection', 'modify', conn_id, '-ipv6.addresses', res_ipv6addr)
      end
    end
  end

  def flush
    return if @property_flush.empty?

    @connection_data = nil
    @conn_info = nil

    destroy
    create
  end
end
