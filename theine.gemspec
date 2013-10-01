Gem::Specification.new do |s|
  s.name        = 'theine'
  s.version     = '0.0.2'
  s.summary     = "Theine"
  s.description = "A Rails preloader for JRuby"
  s.authors     = ["Jan Berdajs"]
  s.email       = 'mrbrdo@mrbrdo.net'
  s.files       = ["lib/theine.rb", "lib/theine/client.rb",
                   "lib/theine/server.rb", "lib/theine/instance.rb"]
  s.executables << 'theine'
  s.executables << 'theine_server'
  s.executables << 'theine_set_ruby'
  s.homepage    = 'https://github.com/mrbrdo/theine'
  s.license     = 'MIT'
end
