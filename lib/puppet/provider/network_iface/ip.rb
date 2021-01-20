require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_iface).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network interfaces.'

  commands ip: 'ip'
  commands brctl: 'brctl'

  def initialize(value = {})
    super(value)
    @property_flush = {}
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
    return config_path unless config_path.nil? || config_path.empty?
    "/etc/sysconfig/network-scripts/ifcfg-#{sfx}"
  end

  def ifcfg_data
    @data ||= self.class.parse_config(config_path)
  end

  mk_resource_methods

  def linkinfo_show
    name = @resource[:name]
    @desc ||= self.class.linkinfo_show(name)
  end

  def addrinfo_show
    name = @resource[:name]
    @addr ||= self.class.addrinfo_show(name)
  end

  def ipv6addr_secondaries
    ifcfg_data['ipv6addr_secondaries'].split.map { |a| a.strip } if ifcfg_data['ipv6addr_secondaries']
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
    ifcfg_ipv6addr  = @resource[:ipv6addr]  || ipv6addr
    ifcfg_ipv6init  = @resource[:ipv6init]  || ipv6init
    ifcfg_prefix    = @resource[:prefix]    || prefix
    ifcfg_ipv6addr_secondaries = @resource[:ipv6addr_secondaries] || ipv6addr_secondaries

    ERB.new(<<-EOF, nil, '<>').result(binding)
<% if ifcfg_device %>
DEVICE=<%= ifcfg_device %>
<% end %>
<% if ifcfg_type %>
TYPE=<%= ifcfg_type %>
<% end %>
<% if ifcfg_ipaddr %>
IPADDR=<%= ifcfg_ipaddr %>
<% end %>
<% if ifcfg_netmask %>
NETMASK=<%= ifcfg_netmask %>
<% end %>
<% if ifcfg_network %>
NETWORK=<%= ifcfg_network %>
<% end %>
<% if ifcfg_broadcast %>
BROADCAST=<%= ifcfg_broadcast %>
<% end %>
<% if ifcfg_onboot %>
ONBOOT=<%= ifcfg_onboot %>
<% end %>
<% if ifcfg_name %>
NAME=<%= ifcfg_name %>
<% end %>
<% if ifcfg_prefix %>
PREFIX=<%= ifcfg_prefix %>
<% end %>
<% if ifcfg_ipv6addr %>
IPV6ADDR=<%= ifcfg_ipv6addr %>
<% end %>
<% if ifcfg_ipv6init %>
IPV6INIT=<%= ifcfg_ipv6init %>
<% end %>
<% if ifcfg_ipv6addr_secondaries %>
IPV6ADDR_SECONDARIES="<%= [ifcfg_ipv6addr_secondaries].flatten.join(' ') %>"
<% end %>
EOF
  end

  def create
    name       = @resource[:name]
    kind       = @resource[:link_kind]
    ifcfg_type = @resource[:conn_type] || conn_type

    case kind
    when :veth
      peer = @resource[:peer_name]
      # ip link add o-hm0 type veth peer name o-bhm0
      self.class.link_create(name, 'type', 'veth', 'peer', 'name', peer)
    end

    f = File.open(config_path_new, 'w', 0o600)
    f.write(ifcfg_content)
    f.close

    return unless ifcfg_type

    ENV['PATH'] = ['/etc/sysconfig/network-scripts', ENV['PATH']].join(':')
    self.class.system_caller('ifup', config_path_new)
  end

  def link_kind
    linkinfo_show['link-kind']
  end

  def peer_name
    linkinfo_show['iflink'] || :absent
  end

  def peer_name=(peer)
    @property_flush[:peer_name] = peer
  end

  def bridge
    if linkinfo_show['slave-kind'] == 'bridge_slave'
      linkinfo_show['master']
    else
      :absent
    end
  end

  def bridge=(brname)
    name = @resource[:name]
    if linkinfo_show['slave-kind'] == 'bridge_slave'
      if brname == :absent
        brctl_caller('delif', brname, name)
      else
        raise Puppet::Error, _("device #{name} is already a member of a bridge") unless linkinfo_show['master'] == brname
      end
    else
      # eg brctl addif brqfc32e1e1-6f o-bhm0
      brctl_caller('addif', brname, name)
    end
    @property_flush[:bridge] = brname
  end

  def destroy
    name = @resource[:name]

    self.class.link_delete(name)
  end

  def exists?
    name = @resource[:name]
    # no ifname - no  device
    linkinfo_show['ifname'] == name
  end

  def flush
    return if @property_flush.empty?
    ifcfg_type = @resource[:conn_type] || conn_type

    f = File.open(config_path_new, 'w', 0o600)
    f.write(ifcfg_content)
    f.close

    return unless ifcfg_type

    ENV['PATH'] = ['/etc/sysconfig/network-scripts', ENV['PATH']].join(':')
    self.class.system_caller('ifup', config_path_new)
  end
end
