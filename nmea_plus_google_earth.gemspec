# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nmea_plus_google_earth/version'

Gem::Specification.new do |spec|
  spec.name          = "nmea_plus_google_earth"
  spec.description   = %q{Converts incoming NMEA/AIS data to a live Google Earth
                          overlay of ship positions}
  spec.version       = NMEAPlusGoogleEarth::VERSION
  spec.licenses      = ['Apache-2.0']
  spec.authors       = ["Ian Katz"]
  spec.email         = ["ianfixes@gmail.com"]

  spec.summary       = spec.description
  spec.homepage      = "http://github.com/ianfixes/nmea_plus_google_earth"

  spec.files         =  ['README.md', '.yardopts'] + Dir['lib/**/*.*'].reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '~> 2.0'

end
