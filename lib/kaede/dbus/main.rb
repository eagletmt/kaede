# Based on DBus::Main in ruby-dbus gem.
# Stop the main loop as quick as possible.
require 'sleepy_penguin'

module Kaede
  module DBus
    class Main
      def initialize
        @buses = Hash.new
        @quit_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      end

      def <<(bus)
        @buses[bus.message_queue.socket] = bus
      end

      def quit
        @quit_event.incr(1)
      end

      def loop
        flush_buffers

        epoll = prepare_epoll
        begin
          while !@buses.empty?
            epoll.wait do |events, io|
              if io == @quit_event
                io.value
                return
              end
              handle_socket(io)
            end
          end
        ensure
          epoll.close
        end
      end

      def handle_socket(socket)
        bus = @buses[socket]
        begin
          bus.message_queue.buffer_from_socket_nonblock
        rescue EOFError, SystemCallError
          @buses.delete(socket) # this bus died
          return
        end
        while message = bus.message_queue.message_from_buffer_nonblock
          bus.process(message)
        end
      end

      def flush_buffers
        # before blocking, empty the buffers
        # https://bugzilla.novell.com/show_bug.cgi?id=537401
        @buses.each_value do |b|
          while m = b.message_queue.message_from_buffer_nonblock
            b.process(m)
          end
        end
      end

      def prepare_epoll
        SleepyPenguin::Epoll.new.tap do |epoll|
          epoll.add(@quit_event, [:IN])
          @buses.each_key do |socket|
            epoll.add(socket, [:IN])
          end
        end
      end
    end
  end
end
