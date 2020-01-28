require 'bundler/setup'
require 'ruby_kml'
require 'webrick'
require 'vincenty'

require_relative 'ship_data'
require_relative 'threadsafe'

SPEED_THRESHOLD = 0.1 # minimum ship speed to consider

module NMEAPlusGoogleEarth

  class GoogleEarthServer

    # save a KML file of the current state of things to `filename`
    def self.write_report_kml(filename, ships)
      File.write(filename, report_kml(ships))
    end

    def self.get_rotated_coordinate(origin, x, y, compass_degrees)
      rads = Math::PI * compass_degrees / 180.0
      cos = Math.cos(rads)
      sin = Math.sin(rads)
      td = Vincenty::TrackAndDistance.from_xy(y * sin + x * cos, y * cos - x * sin)
      origin.destination(td)
    end

    # get KML for a line
    def self.line_kml_of_coordinate_array(name, coords)
      path = coords.map{ |c| "#{c.longitude.to_degrees},#{c.latitude.to_degrees},0"}.join("\n")

      KML::Placemark.new(
        name: name,
        geometry: KML::LineString.new(
          tessellate: true,
          coordinates: path
        )
      )
    end

    def self.polygon_kml_of_ship(name, ship)
      return nil if ship.width.nil? or ship.length.nil? or ship.best_heading.nil? or ship.draft.nil? or ship.coordinate.nil?

      bow_ratio = (ship.length - (ship.width / 2)) / ship.length
      points = [
        [ship.starboard, 0 - ship.stern],
        [0 - ship.port, 0 - ship.stern],
        [0 - ship.port, (ship.length * bow_ratio) - ship.stern],
        [0 - ship.port + (ship.width / 2), ship.bow],
        [ship.starboard, (ship.length * bow_ratio) - ship.stern]
      ]
      points << points[0] # close the drawing

      rotated_coords = points.map { |x, y| get_rotated_coordinate(ship.coordinate, x, y, ship.best_heading) }
      lines = rotated_coords.map { |coord| "#{coord.longitude.to_degrees},#{coord.latitude.to_degrees},#{ship.draft + 1}" }
      border = lines.join("\n")
      poly = KML::Polygon.new(
        extrude: true,
        tessellate: true,
        altitude_mode: 'relativeToGround',
        outer_boundary_is: KML::LinearRing.new(coordinates: border)
      )
      KML::Placemark.new(
        name: name,
        geometry: poly
      )
    end

    # get KML for a point
    def self.point_kml_of_coordinate(name, coord, description = "")
      KML::Placemark.new(
        name: name,
        description: description,
        geometry: KML::Point.new(
          coordinates: {
            lat: coord.latitude.to_degrees,
            lng: coord.longitude.to_degrees,
            alt: 0
          }
        )
      )
    end


    def self.entity_kml_folder(ships)
      entity_folder = KML::Folder.new(name: 'Entities')
      ship_folder = KML::Folder.new(name: 'Ships')
      air_folder = KML::Folder.new(name: 'SAR Aircraft')
      nav_folder = KML::Folder.new(name: 'Navigation Aids')

      ships.each do |mmsi, ship|
        next if ship.coordinate.nil?

        current = ship.coordinate

        pin = point_kml_of_coordinate(ship.best_identifier, current, ship.info)
        shape = polygon_kml_of_ship(ship.best_identifier, ship)

        # display different entities differently
        case ship.mmsi_info.category
        when :coast_station, :harbor_station, :pilot_station, :ais_repeater_station, :aton_physical, :aton_virtual, :aton
          nav_folder.features << pin
          nav_folder.features << shape unless shape.nil?

        when :sar_aircraft, :sar_aircraft_fixed, :sar_aircraft_helicopter
          air_folder.features << pin
          air_folder.features << shape unless shape.nil?

        else


          if ship.speed.nil? || ship.speed <= SPEED_THRESHOLD
            # add pin for fix position
            ship_folder.features << pin
            ship_folder.features << shape unless shape.nil?
          else
            next unless ship.fresh?  # stop printing ships that go off the map WHILE MOVING
            ship_folder.features << pin
            ship_folder.features << shape unless shape.nil?

            unless ship.course.nil? || ship.bow.nil?
              # add line from pin to estimated position
              predicted = ship.estimated_bow_position
              ship_folder.features << line_kml_of_coordinate_array("#{ship.best_identifier} movement", [current, predicted])
            end
          end
        end
      end

      entity_folder.features << ship_folder
      entity_folder.features << nav_folder
      entity_folder.features << air_folder
      entity_folder
    end


    def self.report_kml(ships)
      kml = KMLFile.new
      kml_doc = KML::Document.new

      kml_doc.features << entity_kml_folder(ships)
      kml.objects << kml_doc
      kml.render
    end

    def self.serve_google_earth(server_port, ships_tsw)
      server = WEBrick::HTTPServer.new :Port => server_port
      server.mount_proc '/' do |req, res|
        ships_tsw.safely do |ships|
          res.body = report_kml(ships)
        end
      end
      puts "==================================================================="
      puts "="
      puts "=  Add this network link to Google Earth: http://localhost:#{server_port}"
      puts "="
      puts "==================================================================="
      server.start
    end

  end
end
