spec = Gem::Specification.new do |s|
  s.name = 'monque'
  s.version = '0.1.2'
  s.summary = 'Pre-release beta version of Monque'
  s.author = 'Patrick Collison'
  s.email = 'patrick@collison.ie'
  s.homepage = 'http://collison.ie/monque'
  s.description = 'Simple queue on top of MongoDB, conforming roughly to Resque\'s API'
  s.rubyforge_project = 'monque'
  s.require_paths = %w{lib}

  s.files = %w{
    lib/monque/tasks.rb
    lib/monque.rb
    Rakefile
  }
end
