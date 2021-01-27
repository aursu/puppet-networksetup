require File.expand_path(File.join(File.dirname(__FILE__), '..', 'networksetup'))

Puppet::Type.type(:network_addr).provide(:ip, parent: Puppet::Provider::NetworkSetup) do
  desc 'Manage network address.'

  commands ip: 'ip'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def exists?
    name = @resource[:name]

    # no ifname - no  device
    ifcfg_data['local'] == name
  end

  def ifcfg_data
    name = @resource[:name]

    @addrinfo ||= self.class.addr_lookup(name)
  end

  def device
    ifcfg_data['ifname']
  end

  def label
    ifcfg_data['ifa_label']
  end

  def linkinfo_show
    @linkinfo ||= self.class.linkinfo_show(device)
  end

  def hwaddr
    linkinfo_show['link-addr']
  end

  def destroy
    name = @resource[:name]

    return unless ifcfg_data['local'] == name

    self.class.addr_delete(name, device)
  end

  def get_device_by_hwaddr(hwaddr)
    self.class.get_device_by_hwaddr(hwaddr)
  end

  def create
    name = @resource[:name]
    device = @resource[:device]
    label = @resource[:label]

    return if device.nil? || device.empty?

    args = [name, 'brd', '+', 'dev', device]

    if device == 'lo'
      args += ['scope', 'host']
    end

    if label
      args += ['label', label]
    end

    self.class.addr_create(*args)
  end

  def flush
    return if @property_flush.empty?

    @linkinfo = nil
    @addrinfo = nil

    destroy
    create
  end
end
