require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))
require 'ipaddr'
require 'json'

Puppet::Type.type(:network_iface).provide(:nmcli, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network interfaces using NetworkManager nmcli.'

  initvars
  commands ip: 'ip', nmcli: 'nmcli'

  confine osfamily: :redhat
  defaultfor osfamily: :redhat, operatingsystemmajrelease: ['10']

  mk_resource_methods

  def initialize(value = {})
    super(value)
    @property_flush = {}
    @connection_data = nil
    @ifname = nil
    @linkinfo_iface = nil
    @linkinfo_device = nil
    @linkinfo_name = nil
    @linkinfo = nil
  end

  # --- nmcli helpers ---

  # Run nmcli with given arguments, return output string or nil
  def self.nmcli_caller(*args)
    system_caller(command(:nmcli), *args)
  end

  # Get all connection data as array of hashes
  # Each hash has lowercase field names as keys
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

  # List all connections: returns array of hashes with NAME, UUID, TYPE, DEVICE
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

  # Find connection by interface name, device name or connection name
  def self.find_connection(name, conn_name = nil, device = nil)
    connections = nmcli_connection_list

    # Try exact match by device
    conn = connections.find { |c| c['device'] == name }
    return conn if conn

    # Try by connection name
    if conn_name
      conn = connections.find { |c| c['name'] == conn_name }
      return conn if conn
    end

    # Try by device field matching device parameter
    if device && device != name
      conn = connections.find { |c| c['device'] == device }
      return conn if conn
    end

    # Try by connection name matching interface name
    conn = connections.find { |c| c['name'] == name }
    conn
  end

  # --- Connection data access ---

  def connection_info
    name = @resource[:name]
    device = @resource[:device]
    conn_name = @resource[:conn_name]

    @conn_info ||= self.class.find_connection(name, conn_name, device)
  end

  def connection_data
    return @connection_data if @connection_data

    info = connection_info
    return {} unless info

    # Use UUID for reliable lookup
    @connection_data = self.class.nmcli_connection_show(info['uuid'])
  end

  # Map nmcli connection data fields to provider properties
  NM_FIELD_MAP = {
    'connection.id'             => 'conn_name',
    'connection.uuid'           => 'uuid',
    'connection.type'           => 'conn_type_nm',
    'connection.interface-name' => 'device',
    'connection.autoconnect'    => 'onboot',
    'connection.master'         => 'master',
    'connection.slave-type'     => 'slave_type',
    'ipv4.method'               => 'bootproto_nm',
    'ipv4.addresses'            => 'ipv4_addresses',
    'ipv4.gateway'              => 'gateway',
    'ipv4.dns'                  => 'dns_nm',
    'ipv4.never-default'        => 'ipv4_never_default',
    'ipv6.method'               => 'ipv6_method',
    'ipv6.addresses'            => 'ipv6_addresses',
    'ipv6.gateway'              => 'ipv6_defaultgw',
    'ipv6.never-default'        => 'ipv6_never_default',
    '802-3-ethernet.mac-address' => 'hwaddr',
  }.freeze

  # Convert NM connection type to legacy TYPE value
  def self.nm_type_to_legacy(nm_type)
    case nm_type
    when '802-3-ethernet', 'ethernet'
      'Ethernet'
    when '802-11-wireless', 'wifi'
      'Wireless'
    when 'bridge'
      'Bridge'
    when 'bond'
      'Bond'
    when 'vlan'
      'VLAN'
    when 'team'
      'Team'
    when 'infiniband'
      'InfiniBand'
    when 'loopback'
      'loopback'
    else
      nm_type
    end
  end

  # Convert legacy TYPE to NM connection type
  def self.legacy_type_to_nm(legacy_type)
    case legacy_type
    when 'Ethernet'
      'ethernet'
    when 'Wireless'
      'wifi'
    when 'Bridge'
      'bridge'
    when 'Bond'
      'bond'
    when 'VLAN'
      'vlan'
    when 'Team'
      'team'
    when 'InfiniBand', 'infiniband'
      'infiniband'
    when 'loopback'
      'loopback'
    else
      'ethernet'
    end
  end

  # Convert NM bootproto to legacy BOOTPROTO value
  def self.nm_method_to_bootproto(method)
    case method
    when 'auto'
      'dhcp'
    when 'manual'
      'none'
    when 'disabled'
      'none'
    else
      method
    end
  end

  # Convert legacy BOOTPROTO to NM method
  def self.bootproto_to_nm_method(bootproto)
    case bootproto
    when 'dhcp', 'bootp'
      'auto'
    when 'static', 'none'
      'manual'
    else
      'manual'
    end
  end

  # --- link info (reuse parent class methods) ---

  def interface_name
    addr = @resource[:hwaddr]
    @ifname ||= self.class.get_device_by_hwaddr(addr)
  end

  def linkinfo_iface
    @linkinfo_iface ||= self.class.linkinfo_show(interface_name)
  end

  def linkinfo_device
    device = @resource[:device]
    @linkinfo_device ||= self.class.linkinfo_show(device)
  end

  def linkinfo_name
    name = @resource[:name]
    @linkinfo_name ||= self.class.linkinfo_show(name)
  end

  def linkinfo_show
    @linkinfo ||= linkinfo_iface unless linkinfo_iface.empty?
    return @linkinfo if @linkinfo

    @linkinfo ||= linkinfo_device unless linkinfo_device.empty?
    return @linkinfo if @linkinfo

    @linkinfo ||= linkinfo_name
  end

  def addrinfo_show
    name = linkinfo_show['ifname']
    @addr ||= self.class.addrinfo_show(name)
  end

  def host_number(addr = nil)
    addr = validate_ip(addr)
    addr.to_i.to_s(16).rjust(8, '0') if addr
  end

  # --- property getters from NM connection data ---

  def conn_name
    connection_data['connection.id']
  end

  def uuid
    connection_data['connection.uuid']
  end

  def device
    connection_data['connection.interface-name']
  end

  def conn_type
    nm_type = connection_data['connection.type']
    self.class.nm_type_to_legacy(nm_type) if nm_type
  end

  def onboot
    val = connection_data['connection.autoconnect']
    case val
    when 'yes', 'true'
      'yes'
    when 'no', 'false'
      'no'
    else
      val
    end
  end

  def bootproto
    method = connection_data['ipv4.method']
    self.class.nm_method_to_bootproto(method) if method
  end

  def ipaddr
    addrs = connection_data['ipv4.addresses']
    return nil unless addrs && !addrs.empty? && addrs != '--'

    # nmcli returns addresses as "IP/PREFIX" possibly multiple separated by ", "
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

  def gateway
    val = connection_data['ipv4.gateway']
    (val && val != '--') ? val : nil
  end

  def broadcast
    # NM doesn't store broadcast separately; compute from IP/prefix
    ip = ipaddr
    pfx = prefix
    return nil unless ip && pfx

    begin
      network = IPAddr.new("#{ip}/#{pfx}")
      # broadcast = network | ~netmask
      mask = (1 << 32) - (1 << (32 - pfx.to_i))
      bcast = (network.to_i | (~mask & 0xffffffff))
      IPAddr.new(bcast, Socket::AF_INET).to_s
    rescue StandardError
      nil
    end
  end

  def network
    ip = ipaddr
    pfx = prefix
    return nil unless ip && pfx

    begin
      IPAddr.new("#{ip}/#{pfx}").to_s
    rescue StandardError
      nil
    end
  end

  def hwaddr
    val = connection_data['802-3-ethernet.mac-address']
    (val && val != '--') ? val.upcase.tr('-', ':') : nil
  end

  def dns
    val = connection_data['ipv4.dns']
    return nil unless val && val != '--' && !val.empty?

    val.split(',').map(&:strip).reject(&:empty?)
  end

  def defroute
    val = connection_data['ipv4.never-default']
    case val
    when 'no', 'false'
      'yes'
    when 'yes', 'true'
      'no'
    else
      nil
    end
  end

  def slave
    master_val = connection_data['connection.master']
    (master_val && master_val != '--' && !master_val.empty?) ? 'yes' : nil
  end

  def master
    val = connection_data['connection.master']
    (val && val != '--' && !val.empty?) ? val : nil
  end

  def nm_controlled
    # On NM-managed systems, everything is NM controlled
    'yes'
  end

  # IPv6 properties
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

  def ipv6_defroute
    val = connection_data['ipv6.never-default']
    case val
    when 'no', 'false'
      'yes'
    when 'yes', 'true'
      'no'
    else
      nil
    end
  end

  def ipv6addr_secondaries
    addrs = connection_data['ipv6.addresses']
    return nil unless addrs && !addrs.empty? && addrs != '--'

    parts = addrs.split(',').map(&:strip)
    return nil if parts.size <= 1

    parts[1..-1]
  end

  def ipv6_autoconf
    method = connection_data['ipv6.method']
    method == 'auto' ? 'yes' : 'no'
  end

  def arpcheck
    nil
  end

  def parent_device
    nil
  end

  # --- link info properties ---

  def link_kind
    linkinfo_show['link-kind']
  end

  def peer_name
    linkinfo_show['iflink'] || :absent
  end

  def peer_name=(peer)
    kind = @resource[:link_kind]

    case kind
    when :veth
      destroy
      create
    else
      @property_flush[:peer_name] = peer
    end
  end

  def bridge
    if linkinfo_show['slave-kind'] == 'bridge_slave'
      linkinfo_show['master']
    else
      :absent
    end
  end

  def bridge=(link)
    kind = @resource[:link_kind]

    case kind
    when :veth
      self.class.link_set(name, 'master', link)
    else
      @property_flush[:bridge] = link
    end
  end

  # --- CRUD operations ---

  def build_nmcli_args
    args = []
    name      = @resource[:name]
    device    = @resource[:device] || name
    res_type  = @resource[:conn_type]

    # For loopback, use 'loopback' type if device is 'lo'
    if device == 'lo'
      nm_type = 'loopback'
    elsif res_type
      nm_type = self.class.legacy_type_to_nm(res_type)
    end

    res_conn_name   = @resource[:conn_name]
    res_ipaddr      = @resource[:ipaddr]
    res_prefix      = @resource[:prefix]
    res_netmask     = @resource[:netmask]
    res_gateway     = @resource[:gateway]
    res_bootproto   = @resource[:bootproto]
    res_onboot      = @resource[:onboot]
    res_dns         = @resource[:dns]
    res_hwaddr      = @resource[:hwaddr]
    res_defroute    = @resource[:defroute]
    res_slave       = @resource[:slave]
    res_master      = @resource[:master]
    res_uuid        = @resource[:uuid]
    res_ipv6init    = @resource[:ipv6init]
    res_ipv6addr    = @resource[:ipv6addr]
    res_ipv6_prefixlength = @resource[:ipv6_prefixlength]
    res_ipv6_defaultgw    = @resource[:ipv6_defaultgw]
    res_ipv6_defroute     = @resource[:ipv6_defroute]
    res_ipv6addr_secondaries = @resource[:ipv6addr_secondaries]

    # Connection name
    conn = res_conn_name || device
    args += ['con-name', conn]

    # Connection type
    args += ['type', nm_type] if nm_type

    # Interface name
    args += ['ifname', device]

    # Autoconnect
    if res_onboot
      autoconnect = (res_onboot == 'yes') ? 'yes' : 'no'
      args += ['connection.autoconnect', autoconnect]
    end

    # IPv4 settings
    if res_bootproto
      args += ['ipv4.method', self.class.bootproto_to_nm_method(res_bootproto)]
    elsif res_ipaddr
      args += ['ipv4.method', 'manual']
    end

    if res_ipaddr
      pfx = res_prefix
      unless pfx
        if res_netmask
          pfx = self.class.netmask_prefix(res_netmask)
        end
      end
      pfx ||= 32
      args += ['ipv4.addresses', "#{res_ipaddr}/#{pfx}"]
    end

    if res_gateway
      args += ['ipv4.gateway', res_gateway] unless res_gateway == 'none'
    end

    # DNS
    if res_dns
      dns_list = [res_dns].flatten.compact
      unless dns_list.empty?
        args += ['ipv4.dns', dns_list.join(',')]
      end
    end

    # Default route
    if res_defroute
      never_default = (res_defroute == 'yes') ? 'no' : 'yes'
      args += ['ipv4.never-default', never_default]
    end

    # MAC address
    if res_hwaddr
      args += ['802-3-ethernet.mac-address', res_hwaddr]
    end

    # Master/slave
    if res_slave == 'yes' && res_master
      args += ['connection.master', res_master]
      args += ['connection.slave-type', 'bond']
    end

    # IPv6 settings
    if res_ipv6init == 'yes'
      ipv6_method = 'manual'

      if res_ipv6addr
        addr_v6 = res_ipv6addr
        if res_ipv6_prefixlength && !addr_v6.include?('/')
          addr_v6 = "#{addr_v6}/#{res_ipv6_prefixlength}"
        elsif !addr_v6.include?('/')
          addr_v6 = "#{addr_v6}/64"
        end

        ipv6_addrs = [addr_v6]

        if res_ipv6addr_secondaries
          secondaries = [res_ipv6addr_secondaries].flatten
          ipv6_addrs += secondaries
        end

        args += ['ipv6.method', ipv6_method]
        args += ['ipv6.addresses', ipv6_addrs.join(',')]
      else
        args += ['ipv6.method', 'auto']
      end

      if res_ipv6_defaultgw
        args += ['ipv6.gateway', res_ipv6_defaultgw]
      end

      if res_ipv6_defroute
        never_default_v6 = (res_ipv6_defroute == 'yes') ? 'no' : 'yes'
        args += ['ipv6.never-default', never_default_v6]
      end
    else
      args += ['ipv6.method', 'disabled']
    end

    args
  end

  def create
    name = @resource[:name]
    kind = @resource[:link_kind]

    case kind
    when :veth
      peer = @resource[:peer_name]
      return self.class.link_create(name, 'type', 'veth', 'peer', 'name', peer)
    end

    nocreate = @resource[:nocreate]
    args = build_nmcli_args

    # Check if connection already exists (e.g. loopback)
    if connection_info
      return if nocreate

      conn_id = connection_info['uuid'] || connection_info['name']

      # Build modify arguments: strip con-name, type, ifname which can't be modified
      modify_args = []
      skip_next = false
      args.each_with_index do |arg, _i|
        if skip_next
          skip_next = false
          next
        end
        if ['con-name', 'type', 'ifname'].include?(arg)
          skip_next = true
          next
        end
        modify_args << arg
      end

      self.class.nmcli_caller('connection', 'modify', conn_id, *modify_args) unless modify_args.empty?

      res_type = @resource[:conn_type]
      if res_type
        self.class.nmcli_caller('connection', 'up', conn_id)
      end
    else
      return if nocreate

      self.class.nmcli_caller('connection', 'add', *args)

      # Bring up the connection if type is set
      res_type = @resource[:conn_type]
      if res_type
        conn = @resource[:conn_name] || @resource[:device] || name
        self.class.nmcli_caller('connection', 'up', conn)
      end
    end
  end

  def destroy
    name = @resource[:name]
    kind = @resource[:link_kind]

    case kind
    when :veth
      return self.class.link_delete(name)
    end

    info = connection_info
    if info
      conn_id = info['uuid'] || info['name']
      self.class.nmcli_caller('connection', 'down', conn_id)
      self.class.nmcli_caller('connection', 'delete', conn_id)
    end
  end

  def exists?
    kind     = @resource[:link_kind]
    nocreate = @resource[:nocreate]
    name     = @resource[:name]

    # VETH Type Support - no config
    case kind
    when :veth
      return true if linkinfo_show['ifname']
    end

    # Check if NM connection exists
    info = connection_info

    # Loopback always exists
    return true if name == 'lo' && linkinfo_show['ifname']

    if linkinfo_show['ifname'].is_a?(String)
      return true if info
      return true if nocreate
    end

    false
  end

  def flush
    return if @property_flush.empty?

    nocreate = @resource[:nocreate]
    info = connection_info

    return if nocreate && !info

    if info
      args = build_nmcli_args
      conn_id = info['uuid'] || info['name']

      # Build modify arguments (skip con-name and ifname for modify)
      modify_args = []
      skip_next = false
      args.each_with_index do |arg, i|
        if skip_next
          skip_next = false
          next
        end
        # Skip con-name and type args for modify (they can't be changed)
        if ['con-name', 'type', 'ifname'].include?(arg)
          skip_next = true
          next
        end
        modify_args << arg
      end

      self.class.nmcli_caller('connection', 'modify', conn_id, *modify_args) unless modify_args.empty?

      res_type = @resource[:conn_type] || conn_type
      if res_type
        self.class.nmcli_caller('connection', 'up', conn_id)
      end
    else
      create
    end
  end
end
