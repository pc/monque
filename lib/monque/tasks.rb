namespace :monque do
  task :work do    
    raise "Must specify QUEUES env var" if ENV['QUEUES'].nil?
    raise "Must specify mongo host:port" if ENV['MONGO'].nil?
    
    queues = ENV['QUEUES'].split(',')
    mongo = ENV['MONGO'].split(':')
        
    worker = Monque::Worker.new(mongo[0], mongo[1], queues)
    worker.work
  end
end