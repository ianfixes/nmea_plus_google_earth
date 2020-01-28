require 'bundler/setup'
require 'vincenty'
require 'iso_country_codes'
require_relative './ascii_art'


module NMEAPlusGoogleEarth

  # a class for storing all data about a ship, including extracting it from parsed messages
  class ShipData
    attr_accessor :mmsi
    attr_reader :mmsi_info
    attr_reader :draft
    attr_reader :callsign
    attr_reader :name
    attr_reader :destination
    attr_reader :cargo_type
    attr_reader :speed
    attr_reader :coordinate
    attr_reader :course
    attr_reader :true_heading
    attr_reader :bow
    attr_reader :stern
    attr_reader :port
    attr_reader :starboard
    attr_reader :navigational_status
    attr_reader :new_navigational_status

    def initialize
      @last_touch = Time.now
      @last_fix = nil
      @bow = 0
      @stern = 0
      @port = 0
      @starboard = 0
      @draft = nil
      @callsign = nil
      @name = nil
      @destination = nil
      @cargo_type = nil
      @speed = nil
      @coordinate = nil
      @course = nil
      @true_heading = nil # seems bogus
      @navigational_status = nil
      @new_navigational_status = nil
      @mmsi_info = nil
    end

    def best_identifier
      return @name unless @name.nil?
      return @callsign unless @callsign.nil?
      @mmsi # guaranteed
    end

    def seconds_since_last_contact
      Time.now - @last_touch
    end

    def fresh?
      seconds_since_last_contact < 600
    end

    def length
      return nil if @bow.nil?
      return nil if @stern.nil?
      ret = @bow + @stern
      return nil if ret == 0
      ret.to_f
    end

    def width
      return nil if @port.nil?
      return nil if @starboard.nil?
      ret = @port + @starboard
      return nil if ret == 0
      ret.to_f
    end

    def best_heading
      return @true_heading unless @true_heading.nil?
      @course
    end

    def shape
      return nil if length.nil? || width.nil? || @draft.nil?
      return nil if length == 0 && width == 0 && @draft == 0
      #AsciiArt.rect_prism(length / 20, @draft / 10, width / 20, best_identifier)
      return nil if @bow.nil? || length == 0
      l = length / 10
      w = width / 10
      d = @draft / 3  # typical numbers: 0 for passenger ferries, 5 for tugs, and 10.3 for big ships
                          # tall skinny ships look weird, so limit our height to the minimum other dimension
      AsciiArt.boat(l, w, [l, w - 1, d].min, (length.to_f - @bow.to_f) / length.to_f, best_identifier)
    end

    def speed_ms
      return nil if @speed.nil?
      @speed * 1852.0 / 3600.0
    end

    def estimated_meters_travelled
      return nil if speed_ms.nil?
      time_since_fix = Time.now - @last_fix
      speed_ms * time_since_fix
    end

    def estimated_position
      return nil if @coordinate.nil?
      return nil if @course.nil?
      track = Vincenty::TrackAndDistance.new(@course, estimated_meters_travelled)
      @coordinate.destination(track)
    end

    def estimated_bow_position
      return nil if @coordinate.nil?
      return nil if @course.nil?
      return nil if @bow.nil?
      track = Vincenty::TrackAndDistance.new(@course, estimated_meters_travelled + @bow)
      @coordinate.destination(track)
    end

    def estimated_meters_to(point)
      est_position = estimated_position
      return nil if est_position.nil?
      bow_correction = @bow.nil? ? 0 : @bow
      est_position.distanceAndAngle(point).distance - bow_correction
    end

    def eta_to_point(point, epsilon_course_degrees)
      # we need speed
      spd = speed_ms
      return nil if spd.nil? || spd <= 0

      # we need location and course to check whether we're headed toward the point
      return nil if @coordinate.nil?
      return nil if @course.nil?
      bearing = @coordinate.distanceAndAngle(point).bearing
      return nil if epsilon_course_degrees < ((bearing.to_degrees - @course).abs % 360)

      # we need distance to point
      distance = estimated_meters_to(point)
      return nil if distance < 0


      distance / spd
    end

    # intersection with a vincenty segment
    def estimated_intersection_point(segment)
      l = estimated_line
      return nil if l.nil?
      return nil unless l.intersects?(segment)
      l.projected_intersection(segment)
    end

    # eta to intersection with a vincenty segment
    def eta_to_segment(segment)
      point = estimated_intersection_point(segment)
      return nil if point.nil?
      eta_to_point(point, 1)
    end

    # return a vincenty line representing the ship's current location and bearing
    def line
      return nil if @coordinate.nil?
      return nil if @course.nil?
      return Vincenty::Line.new(@coordinate, @course)
    end

    # return a vincenty line representing the ship's current location and bearing
    def estimated_line
      pos = estimated_position
      return nil if pos.nil?
      return nil if @course.nil?
      return Vincenty::Line.new(pos, @course)
    end

    def info
      flag = begin
        country = IsoCountryCodes.find(@mmsi_info.country_id).name
        " under #{country} flag"
      rescue IsoCountryCodes::UnknownCodeError
        nil
      end

      l1 = "(#{@mmsi.to_s.rjust(10, ' ')}) #{@mmsi_info.category_description}"
      l1 << " #{@name}" unless @name.nil?
      l1 << " (#{@callsign})" unless @callsign.nil?
      l1 << ": '#{@cargo_type}'" unless @cargo_type.nil?
      l1 << flag unless flag.nil?
      l1 << ", bound for #{@destination}" unless @destination.nil?
      l1 << ", #{@navigational_status}" unless @navigational_status.nil?
      ret = [l1]

      ret << "  at #{@coordinate} heading #{@course} (#{@true_heading}) @ #{@speed}kts" if [@coordinate, @course, @true_heading, @speed].all?

      shape_str = shape
      ret << shape_str unless shape_str.nil?
      ret.join("\n")
    end

    def set_dimensions(ais)
      @bow       = ais.ship_dimension_to_bow unless ais.ship_dimension_to_bow.nil?
      @stern     = ais.ship_dimension_to_stern unless ais.ship_dimension_to_stern.nil?
      @port      = ais.ship_dimension_to_port unless ais.ship_dimension_to_port.nil?
      @starboard = ais.ship_dimension_to_starboard unless ais.ship_dimension_to_starboard.nil?
    end

    # common to all messages: update mmsi category
    def set_msg(ais)
      @last_touch = Time.now
      @mmsi_info = ais.source_mmsi_info
    end

    # common to ais messages that set a location
    def set_position(ais)
      return if ais.latitude.nil? || ais.longitude.nil?
      @coordinate = Vincenty::Coordinate.new(ais.latitude, ais.longitude)
      @last_fix = Time.now
    end

    # move the new status to the current status
    def acknowledge_navigational_status
      @navigational_status = @new_navigational_status
      @new_navigational_status = nil
    end

    def set_msg_123(ais)
      @speed = ais.speed_over_ground
      set_position(ais)
      @course = ais.course_over_ground
      @true_heading = ais.true_heading

      # if no status, update immediately.  otherwise put into pending if it's different than what's currently there
      if @navigational_status.nil?
        @navigational_status = ais.navigational_status_description
      elsif @navigational_status != ais.navigational_status_description
        @new_navigational_status = ais.navigational_status_description
      end

      #expect(parsed.ais.rate_of_turn).to eq(nil)
    end

    def set_msg_4(ais)
      set_position(ais)
    end

    def set_msg_5(ais)
      set_dimensions(ais)
      @draft = ais.static_draught
      @name = ais.name.strip unless ais.name.nil? || ais.name.empty?
      @callsign = ais.callsign.strip unless ais.callsign.nil? || ais.callsign.empty?
      @cargo_type = ais.ship_cargo_type_description
      @destination = ais.destination.strip unless ais.destination.nil? || ais.destination.empty?

    end

    def set_msg_9(ais)
      @speed = ais.speed_over_ground
      set_position(ais)
      @course = ais.course_over_ground
      # TODO: altitude?
    end

    def set_msg_18(ais)
      @speed = ais.speed_over_ground
      set_position(ais)
      @course = ais.course_over_ground
      @true_heading = ais.true_heading
    end

    def set_msg_19(ais)
      set_dimensions(ais)
      @name = ais.name.strip unless ais.name.empty?
      @cargo_type = ais.ship_cargo_type_description
    end

    def set_msg_21(ais)
      set_position(ais)

      set_dimensions(ais)
      full_name = ais.name.strip
      full_name << ais.name_extension.strip unless ais.name_extension.nil?

      @name = full_name unless full_name.empty?
    end

    def set_msg_24(ais)
      case ais.part_number
      when 0
        @name = ais.name.strip unless ais.name.empty?
      when 1
        unless ais.auxiliary_craft?
          set_dimensions(ais)
        end
      end

    end

  end
end
