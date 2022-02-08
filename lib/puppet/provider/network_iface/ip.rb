require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))
require 'ipaddr'

Puppet::Type.type(:network_iface).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network interfaces.'

  initvars
  commands ip: 'ip'
  defaultfor osfamily: :redhat

  mk_resource_methods

  def initialize(value = {})
    super(value)
    @property_flush = {}
    @config = nil
    @addrinfo = nil
    @ifname = nil
    @linkinfo_iface = nil
    @linkinfo_device = nil
    @linkinfo_name = nil
    @linkinfo = nil
  end

  def config_path
    name = @resource[:name]
    device = @resource[:device]
    conn_name = @resource[:conn_name]

    @config ||= self.class.config(name, conn_name)

    return @config if @config || device.nil? || device.empty? || device == name

    @config ||= self.class.config(device, conn_name)
  end

  def config_path_new
    name = @resource[:name]
    device = @resource[:device]

    sfx = device || name

    # try to use existing configuration first
    return config_path if config_path
    "/etc/sysconfig/network-scripts/ifcfg-#{sfx}"
  end

  def ifcfg_data
    @addrinfo ||= self.class.parse_config(config_path)
  end

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

  # return Array of Hashes with interface addresses' infor or empty array
  def addrinfo_show
    name = linkinfo_show['ifname']
    @addr ||= self.class.addrinfo_show(name)
  end

  def host_number(addr = nil)
    addr = validate_ip(addr)
    addr.to_i.to_s(16).rjust(8, '0') if addr
  end

  def ipv6addr_secondaries
    ifcfg_data['ipv6addr_secondaries'].split.map { |a| a.strip } if ifcfg_data['ipv6addr_secondaries']
  end

  def ipv6_prefixlength
    ipv6addr.split('/')[1] if ipv6addr
  end

  def ifcfg_content
    ifcfg_device    = @resource[:device]    || device
    ifcfg_ipaddr    = @resource[:ipaddr]    || ipaddr
    ifcfg_netmask   = @resource[:netmask]   || netmask
    ifcfg_network   = @resource[:network]   || network
    ifcfg_broadcast = @resource[:broadcast] || broadcast
    ifcfg_onboot    = @resource[:onboot]    || onboot
    ifcfg_name      = @resource[:conn_name] || conn_name
    ifcfg_type      = @resource[:conn_type] || conn_type
    ifcfg_ipv6init  = @resource[:ipv6init]  || ipv6init
    ifcfg_prefix    = @resource[:prefix]    || prefix
    ifcfg_ipv6addr_secondaries = @resource[:ipv6addr_secondaries] || ipv6addr_secondaries
    ifcfg_ipv6_defaultgw = @resource[:ipv6_defaultgw] || ipv6_defaultgw
    ifcfg_ipv6_defroute = @resource[:ipv6_defroute] || ipv6_defroute
    ifcfg_bootproto = @resource[:bootproto] || bootproto
    ifcfg_defroute  = @resource[:defroute]  || defroute
    ifcfg_gateway   = @resource[:gateway]   || gateway
    ifcfg_hwaddr    = @resource[:hwaddr]    || hwaddr
    ifcfg_dns       = @resource[:dns]       || dns
    ifcfg_dns       = [ifcfg_dns].flatten if ifcfg_dns
    ifcfg_slave     = @resource[:slave]     || slave
    ifcfg_master    = @resource[:master]    || master
    ifcfg_nm_controlled = @resource[:nm_controlled] || nm_controlled
    ifcfg_uuid      = @resource[:uuid]      || uuid

    res_ipv6addr = @resource[:ipv6addr]
    res_prefixlength = @resource[:ipv6_prefixlength]
    if res_ipv6addr
      addr, plen = res_ipv6addr.split('/')
      plen = res_prefixlength if res_prefixlength

      res_ipv6addr = if plen
                       [addr, plen].join('/')
                     else
                       addr
                     end
    end
    ifcfg_ipv6addr = res_ipv6addr || ipv6addr

    ERB.new(<<-EOF, nil, '<>').result(binding)
<% if ifcfg_uuid %>
UUID=<%= ifcfg_uuid %>
<% end %>
<% if ifcfg_type %>
TYPE=<%= ifcfg_type %>
<% end %>
<% if ifcfg_bootproto %>
BOOTPROTO=<%= ifcfg_bootproto %>
<% end %>
<% if ifcfg_defroute %>
DEFROUTE=<%= ifcfg_defroute %>
<% end %>
<% if ifcfg_ipv6init %>
IPV6INIT=<%= ifcfg_ipv6init %>
<% end %>
<% if ifcfg_name %>
NAME=<%= ifcfg_name %>
<% end %>
<% if ifcfg_device %>
DEVICE=<%= ifcfg_device %>
<% end %>
<% if ifcfg_hwaddr %>
HWADDR=<%= ifcfg_hwaddr %>
<% end %>
<% if ifcfg_nm_controlled %>
NM_CONTROLLED=<%= ifcfg_nm_controlled %>
<% end %>
<% if ifcfg_onboot %>
ONBOOT=<%= ifcfg_onboot %>
<% end %>
<% if ifcfg_ipaddr %>
IPADDR=<%= ifcfg_ipaddr %>
<% end %>
<% if ifcfg_prefix %>
PREFIX=<%= ifcfg_prefix %>
<% end %>
<% if ifcfg_netmask %>
NETMASK=<%= ifcfg_netmask %>
<% end %>
<% if ifcfg_network %>
NETWORK=<%= ifcfg_network %>
<% end %>
<% if ifcfg_gateway %>
GATEWAY=<%= ifcfg_gateway %>
<% end %>
<% if ifcfg_broadcast %>
BROADCAST=<%= ifcfg_broadcast %>
<% end %>
<% if ifcfg_ipv6addr %>
IPV6ADDR=<%= ifcfg_ipv6addr %>
<% end %>
<% if ifcfg_ipv6addr_secondaries %>
IPV6ADDR_SECONDARIES="<%= [ifcfg_ipv6addr_secondaries].flatten.join(' ') %>"
<% end %>
<% if ifcfg_ipv6_defaultgw %>
IPV6_DEFAULTGW=<%= ifcfg_ipv6_defaultgw %>
<% end %>
<% if ifcfg_ipv6_defroute %>
IPV6_DEFROUTE=<%= ifcfg_ipv6_defroute %>
<% end %>
<% if ifcfg_dns %>
<% for i in 1..ifcfg_dns.size do %>
DNS<%= i %>=<%= ifcfg_dns[i - 1] %>
<% end %>
<% end %>
<% if ifcfg_master && ifcfg_slave  %>
SLAVE=<%= ifcfg_slave %>
MASTER=<%= ifcfg_master %>
<% end %>
EOF
  end

  def create
    name       = @resource[:name]
    kind       = @resource[:link_kind]

    case kind
    when :veth
      peer = @resource[:peer_name]
      # ip link add o-hm0 type veth peer name o-bhm0
      # ip link add <name> type <link_kind> peer name <peer_name>
      return self.class.link_create(name, 'type', 'veth', 'peer', 'name', peer)
    end

    ifcfg_type = @resource[:conn_type] || conn_type
    nocreate   = @resource[:nocreate]

    ifcfg = config_path_new
    return if nocreate && !File.exist?(ifcfg)

    f = File.open(ifcfg, 'w', 0o600)
    f.write(ifcfg_content)
    f.close

    # run ifup command only if TYPE is set in ifcfg configuration script
    return unless ifcfg_type

    self.class.system_caller('ifup', ifcfg)
  end

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
      # remove current device and create new with updated peer
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

  def destroy
    name = @resource[:name]

    self.class.link_delete(name)
  end

  def exists?
    kind     = @resource[:link_kind]
    nocreate = @resource[:nocreate]

    # VETH Type Support - no config
    case kind
    when :veth
      return true if linkinfo_show['ifname']
    end

    ifcfg = config_path
    # no ifname - no  device
    if linkinfo_show['ifname'].is_a?(String)
      # we want to have both device and its ifcfg script
      return true if ifcfg
      return true if nocreate
    end

    false
  end

  def flush
    return if @property_flush.empty?
    ifcfg_type = @resource[:conn_type] || conn_type
    nocreate   = @resource[:nocreate]

    ifcfg = config_path_new

    return if nocreate && !File.exist?(ifcfg)

    f = File.open(ifcfg, 'w', 0o600)
    f.write(ifcfg_content)
    f.close

    # run ifup command only if TYPE is set in ifcfg configuration script
    return unless ifcfg_type

    self.class.system_caller('ifup', ifcfg)
  end
end
