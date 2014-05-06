module Kaede
  module DBus
    module Properties
      PROPERTY_INTERFACE = 'org.freedesktop.DBus.Properties'

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def properties_method
          @properties_method ||= {}
        end

        def properties_for(iface, method_sym)
          self.properties_method[iface] = method_sym
        end

        def define_properties
          dbus_interface PROPERTY_INTERFACE do
            dbus_method :Get, 'in interface:s, in property:s, out value:v' do |iface, prop|
              if self.class.properties_method.has_key?(iface)
                props = send(self.class.properties_method[iface])
                if props.has_key?(prop)
                  [props[prop]]
                else
                  raise_unknown_property!
                end
              else
                raise_unknown_interface!
              end
            end

            dbus_method :GetAll, 'in interface:s, out properties:a{sv}' do |iface|
              if self.class.properties_method.has_key?(iface)
                [send(self.class.properties_method[iface])]
              else
                unknown_interface!
              end
            end

            dbus_method :Set, 'in interface:s, in property:s, in value:v' do |iface, prop, val|
              raise_access_denied!
            end
          end
        end
      end

      def xml_for_dbus_properties(xml)
        xml.interface(name: PROPERTY_INTERFACE) do
          xml.method_(name: 'Get') do
            xml.arg(name: 'interface', direction: 'in', type: 's')
            xml.arg(name: 'property', direction: 'in', type: 's')
            xml.arg(name: 'value', direction: 'out', type: 'v')
          end

          xml.method_(name: 'GetAll') do
            xml.arg(name: 'interface', direction: 'in', type: 's')
            xml.arg(name: 'properties', direction: 'out', type: 'a{sv}')
          end

          xml.method_(name: 'Set') do
            xml.arg(name: 'interface', direction: 'in', type: 's')
            xml.arg(name: 'property', direction: 'in', type: 's')
            xml.arg(name: 'value', direction: 'in', type: 'v')
          end
        end
      end

      def xml_for_properties(xml)
        xml_for_dbus_properties(xml)
        self.class.properties_method.each do |iface, method_sym|
          xml.interface(name: iface) do
            send(method_sym).each_key do |key|
              xml.property(name: key, type: 's', access: 'read')
            end
          end
        end
      end

      def raise_unknown_interface!
        raise ::DBus.error('org.freedesktop.DBus.Error.UnknownInterface')
      end

      def raise_unknown_property!
        raise ::DBus.error('org.freedesktop.DBus.Error.UnknownProperty')
      end

      def raise_access_denied!
        raise ::DBus.error('org.freedesktop.DBus.Error.AccessDenied')
      end
    end
  end
end
