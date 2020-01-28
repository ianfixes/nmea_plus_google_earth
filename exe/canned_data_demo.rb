#!/usr/bin/env ruby

require 'nmea_plus_google_earth'

# This runs a server based on a stream of canned data recorded in Boston harbor.
# The demo only has a few minutes of data when played back.
#
# It will take a minute or so for the locations, names, and dimensions of ships to come in.

server_port = 7447 # spells SHIP

samples = File.expand_path("../../boston.txt", __FILE__)
io_source = File.open(samples)
# io_source = SerialPort.new("/dev/tty.usbserial", 38400, 8, 1, SerialPort::NONE)

server = NMEAPlusGoogleEarth::GoogleEarthVisualizer.new(server_port)
# we add a sleep of 0.2 seconds to prevent the file from being read and processed instantly.
# this still results in sped-up boat motion but it will be somewhat watchable in google earth
server.process(io_source) { sleep 0.4 }
