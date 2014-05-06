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
              get_property(iface, prop)
            end

            dbus_method :GetAll, 'in interface:s, out properties:a{sv}' do |iface|
              get_properties(iface)
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

      def get_property(iface, prop)
        props = get_properties(iface).first
        if props.has_key?(prop)
          [props[prop]]
        else
          raise_unknown_property!
        end
      end

      def get_properties(iface)
        if sym = self.class.properties_method[iface]
          [send(sym)]
        else
          unknown_interface!
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
