require 'dbus'
require 'nokogiri'
require 'time'

module Kaede
  module DBus
    class Program < ::DBus::Object
      PATH = '/cc/wanko/kaede1/program'
      PROPERTY_INTERFACE = 'org.freedesktop.DBus.Properties'
      INTROSPECT_INTERFACE = 'org.freedesktop.DBus.Introspectable'
      PROGRAM_INTERFACE = 'cc.wanko.kaede1.Program'

      def initialize(program, enqueued_at)
        super("#{PATH}/#{program.pid}")
        @program = program
        @enqueued_at = enqueued_at
      end

      def to_xml
        Nokogiri::XML::Builder.new do |xml|
          xml.doc.create_internal_subset(
            'node',
            '-//freedesktop//DTD D-BUS Object Introspection 1.0//EN',
            'http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd',
          )
          xml.node do
            xml.interface(name: INTROSPECT_INTERFACE) do
              xml.method_(name: 'Introspect') do
                xml.arg(name: 'data', direction: 'out', type: 's')
              end
            end

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

            xml.interface(name: PROGRAM_INTERFACE) do
              properties.each_key do |key|
                xml.property(name: key, type: 's', access: 'read')
              end
            end
          end
        end.to_xml
      end

      dbus_interface PROPERTY_INTERFACE do
        dbus_method :Get, 'in interface:s, in property:s, out value:v' do |iface, prop|
          case iface
          when PROGRAM_INTERFACE
            if properties.has_key?(prop)
              [properties[prop]]
            else
              raise_unknown_property!
            end
          else
            raise_unknown_property!
          end
        end

        dbus_method :GetAll, 'in interface:s, out properties:a{sv}' do |iface|
          case iface
          when PROGRAM_INTERFACE
            [properties]
          when PROGRAM_INTERFACE
            [{}]
          else
            unknown_interface!
          end
        end

        dbus_method :Set, 'in interface:s, in property:s, in value:v' do |iface, prop, val|
          raise_access_denied!
        end
      end

      dbus_interface PROGRAM_INTERFACE do
      end

      def properties
        @properties ||= {
          'Pid' => @program.pid,
          'Tid' => @program.tid,
          'StartTime' => @program.start_time.iso8601,
          'EndTime' => @program.end_time.iso8601,
          'ChannelName' => @program.channel_name,
          'ChannelForSyoboi' => @program.channel_for_syoboi,
          'ChannelForRecorder' => @program.channel_for_recorder,
          'Count' => @program.count,
          'StartOffset' => @program.start_offset,
          'SubTitle' => @program.subtitle,
          'Title' => @program.title,
          'Comment' => @program.comment,
          'EnqueuedAt' => @enqueued_at.iso8601,
        }
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
