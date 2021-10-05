require 'ipaddr'

Puppet::Functions.create_function(:'networksetup::gateway_prediction') do
    dispatch :gateway_prediction do
      param 'Stdlib::IP::Address', :addr
      optional_param 'Stdlib::IP::Address', :mask
    end

    def gateway_prediction(addr, mask = nil)
      addr, prefix = addr.split('/', 2)

      if IPAddr.new(addr).ipv6?
        fullmask = 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
        defprefix = 64
      else
        fullmask = '255.255.255.255'
        defprefix = 24
      end

      prefix = defprefix unless prefix
      mask = IPAddr.new(fullmask).mask(prefix.to_i).to_s unless mask

      IPAddr.new(addr).mask(mask).succ
    end
  end