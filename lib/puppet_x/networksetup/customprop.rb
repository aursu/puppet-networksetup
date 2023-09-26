require 'puppet/property'

#
module PuppetX
  module NetworkSetup
    # yes/no switch
    class SwitchProperty < Puppet::Property
      def self.defaultvalues
        newvalues(:yes, :no, :true, :false, 0, 1)
      end

      munge do |val|
        case val.to_s
        when 'true', 'yes', '1'
          'yes'
        when 'false', 'no', '0'
          'no'
        else
          val.to_s
        end
      end

      validate do |value|
        next if ['yes', 'no', '0', '1', 'true', 'false'].include?(value.to_s)

        raise ArgumentError, _('Invalid value %{value}. Valid values are yes, no, 0, 1, true, false') % { value: value }
      end
    end

    #
    class IPProperty < Puppet::Property
      validate do |value|
        raise Puppet::ParseError, _("Wrong IP address \"#{value}\" for #{name}") unless provider.validate_ip(value)
      end
    end
  end
end
