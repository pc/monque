require 'rubygems'
require 'mongo'
require 'json'

module Kernel
  # from http://redcorundum.blogspot.com/2006/05/kernelqualifiedconstget.html
  def fetch_class(str)
    path = str.to_s.split('::')
    from_root = path[0].empty?
    if from_root
      from_root = []
      path = path[1..-1]
    else
      start_ns = ((Class === self)||(Module === self)) ? self : self.class
      from_root = start_ns.to_s.split('::')
    end
    until from_root.empty?
      begin
        return (from_root+path).inject(Object) { |ns,name| ns.const_get(name) }
      rescue NameError
        from_root.delete_at(-1)
      end
    end
    path.inject(Object) { |ns,name| ns.const_get(name) }
  end
end

module Monque
  RETRY_DELAY = 1800 # wait this number secs before trying a job again
  REPLICATION_FACTOR = 1
  
  @mongo_host = '127.0.0.1'
  @mongo_port = 27017
  
  def self.mongo_host=(h); @mongo_host = h; end
  def self.mongo_port=(p); @mongo_port = p; end
  
  def self.jobs_collection(host=nil, port=nil)
    host ||= @mongo_host
    port ||= @mongo_port
    
    Mongo::Connection.new(host, port)['monque']['jobs']
  end
  
  def self.queue_for_cls(cls)
    if cls.kind_of?(Class) || cls.kind_of?(Module)
      if qname = cls.instance_variable_get(:@queue)
        qname.is_a?(Symbol) ? qname.to_s : qname
      else
        raise "You should define the @queue name for #{cls.inspect}"
      end
    else
      raise TypeError.new("The first argument to enqueue should be a class")
    end
  end
  
  def self.enqueue(cls, *args)
    queue = queue_for_cls(cls)
    raise NameError.new("Invalid queue name: #{queue.inspect}") unless queue.kind_of?(String)
    
    @jobs ||= jobs_collection
    @jobs.save({
      'queue' => queue,
      'class' => cls.name,
      'data' => args.to_json,
      'started' => 0,
      'created' => Time.now.to_f,
      'proc_attempts' => []},
      {:safe => {:w => REPLICATION_FACTOR}}
    )
  end
  
  class Worker
    def initialize(queues)
      @queues = queues
      @jobs = Monque.jobs_collection
    end
    
    def worker_id
      @worker_id ||= "#{`hostname`.strip}-#{$$}-#{Time.now.to_f}"
    end
    
    def reserve
      @queues.each do |q|
        speculative_job = @jobs.find(
          'queue' => q.to_s,
          'started' => {'$lte' => (Time.now.to_f - RETRY_DELAY)},
          'finished' => {'$exists' => false}
        ).sort('added', :ascending).limit(1).first

        next unless speculative_job
        
        old_procid = speculative_job['procid']
                
        gotted_job = @jobs.find_and_modify(
          :query => {
            '_id' => speculative_job['_id'],
            'proc_attempts' => speculative_job['proc_attempts']
          },
          :update => {
            '$set' =>  {'started' => Time.now.to_f},
            '$push' => {
              'proc_attempts' => {
                  'id' => sprintf("%x", rand(1024**3)),
                  'by' => worker_id,
                  'time' => Time.now.to_f
              }
            }
          },
          :new => true
        )
        
        if gotted_job
          return gotted_job
        else
          nil
        end
      end
      
      nil
    end
      
    def mark_finished(job)
      ok = @jobs.find_and_modify(
        :query => {
          '_id' => job['_id'],
          'proc_attempts' => job['proc_attempts']
        },
        :update => job.merge({'finished' => Time.now.to_f})
      )
    rescue Mongo::OperationFailure => e
      if e.message =~ /No matching object found/
        raise "This shouldn't happen - job was marked as finished though I had it reserved."
      else
        raise e
      end
    end
      
    def work
      loop do
        job = reserve
        
        if job         
          cls = Kernel.fetch_class(job['class'])
          $stderr.puts "#{worker_id}: processing #{job.inspect}"
          cls.send(:perform, *JSON.load(job['data']))
          mark_finished(job)
        end
        
        sleep 5
      end
    end
  end
end
