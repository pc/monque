namespace :monque do
  task :work do    
    raise "Must specify QUEUES env var" if ENV['QUEUES'].nil?
    
    queues = ENV['QUEUES'].split(',')
        
    worker = Monque::Worker.new(queues)
    worker.work
  end
end
