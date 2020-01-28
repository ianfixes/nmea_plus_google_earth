require 'nmea_plus'
require 'thread'

require_relative 'ship_data'
require_relative 'google_earth_server'
require_relative 'threadsafe'

GRACE_PERIOD = 600

module NMEAPlusGoogleEarth

  class GoogleEarthVisualizer

    def initialize(server_port)
      @worker_thread_definitions = {}
      @worker_threads = {}

      # serve data for Google Earth
      add_thread_definition("http") do |ships_tsw, _safety_message_tsw|
        Thread.new { GoogleEarthServer.serve_google_earth(server_port, ships_tsw) }
      end

      # report known ships to the console every 30 seconds
      add_thread_definition("reporter") do |ships_tsw, safety_message_tsw|
        Thread.new do
          loop do
            report_info_to_console(ships_tsw, safety_message_tsw)
            sleep(30)
          end
        end
      end

      # forget about ships we haven't heard from in 24h, every 30 minutes
      add_thread_definition("cleaner") do |ships_tsw, _safety_message_tsw|
        Thread.new do
          loop do
            cleanup_old_ships(ships_tsw)
            sleep(1800)
          end
        end
      end
    end

    # A thread definition is a block that takes 2 arguments (thread safe hash wrapper, thread safe string wrapper)
    #  and returns a new thread that acts on those 2 values.
    def add_thread_definition(name, &block)
      puts "Adding thread definition #{name}"
      @worker_thread_definitions[name] = block
    end

    # Start all threads from their definitions
    def start_threads(ships_tsw, safety_message_tsw)
      @worker_thread_definitions.each do |name, d|
        puts "Starting thread: #{name}"
        @worker_threads[name] = d.call(ships_tsw, safety_message_tsw)
      end
    end

    # Stop all defined threads
    def stop_threads
      @worker_threads.each do |name, t|
        puts "Stopping thread: #{name}"
        t.exit
      end
    end

    # Wait for all threads to complete
    def join_threads
      @worker_threads.each do |name, t|
        puts "Joining thread: #{name}"
        t.join
      end
      @worker_threads = {}
    end

    # Log known information to the console
    def report_info_to_console(ships_tsw, safety_message_tsw)
      safety_message_tsw.safely do |safety_message|
        # print a safety message if received
        next if safety_message.empty?

        # the message already has prefix text
        puts safety_message
        safety_message.replace("")
      end

      ships_tsw.safely do |ships|
        puts "reporting on #{ships.length} ships, #{ships.values.select { |s| s.coordinate.nil? }.length } don't have coordinates"
        ships.each do |mmsi, ship|
          next unless ship.fresh?

          puts ship.info
        end
      end
    end

    # when ships haven't been heard from in a day, remove them from memory
    def cleanup_old_ships(ships_tsw)
      ships_tsw.safely do |ships|
        ships.delete_if { |k, v| 86400 < v.seconds_since_last_contact }
      end
    end

    # apply a message to our body of knowledge on ships
    def update_ship_information(ships_tsw, safety_message_tsw, message)
      return unless "VDM" == message.interpreted_data_type

      # We will deal with only one thead-safe struct at a time...
      new_safety_message = nil

      ships_tsw.safely do |ships|
        ais = message.ais
        ship = ships.fetch(ais.source_mmsi, ShipData.new)
        ship.mmsi = ais.source_mmsi

        puts "Heard message #{ais.message_type.to_s.rjust(2, " ")} from #{ship.best_identifier}"

        ship.set_msg(ais)
        case ais.message_type
        when 1, 2, 3
          ship.set_msg_123(ais)
        when 4
          ship.set_msg_4(ais)
        when 5
          ship.set_msg_5(ais)
        when 9
          ship.set_msg_9(ais)
        when 12
          new_safety_message = "Safety-related message from #{ship.best_identifier} for #{ais.destination_mmsi}: `#{ais.text}`"
        when 14
          new_safety_message = "Safety-related broadcast from #{ship.best_identifier}: `#{ais.text}`"
        when 18
          ship.set_msg_18(ais)
        when 19
          ship.set_msg_19(ais)
        when 21
          ship.set_msg_21(ais)
        when 24
          ship.set_msg_24(ais)
        end
        ships[ais.source_mmsi] = ship unless ship.mmsi.nil?
      end

      return if new_safety_message.nil?

      safety_message_tsw.safely do |msg|
        msg.replace(new_safety_message)
      end
    end

    # spawn a listener thread to operate on the source data, and any supporting threads
    #
    # this function takes an optional block, which is what gets done after every iteration.
    # If the source is a file of data collected in realtime, then the optional block would be used
    # to introduce a delay into the processing
    def process(source)
      Thread.abort_on_exception = true
      ships_tsw = ThreadSafeWrapper.new(Hash.new)
      safety_message_tsw = ThreadSafeWrapper.new("")

      start_threads(ships_tsw, safety_message_tsw)

      # listen for AIS messages, constantly
      listener = Thread.new do
        decoder = NMEAPlus::SourceDecoder.new(source)
        decoder.each_complete_message do |message|
          update_ship_information(ships_tsw, safety_message_tsw, message)

          yield if block_given?
          sleep(0.001) # give other threads a chance to work
        end # decoding
        puts "end of decoding, but will keep server running for #{GRACE_PERIOD} more seconds"

        # keep running other threads for a bit, like the http server
        sleep(GRACE_PERIOD)
        stop_threads

      end # thread

      join_threads
      listener.join
    end

  end
end
