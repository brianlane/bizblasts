# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
# Only use one port binding method to avoid conflicts
port ENV.fetch("PORT", 3000)

# Memory-optimized worker configuration
# Use single worker process to minimize memory usage
workers ENV.fetch("WEB_CONCURRENCY", 1)

# Only preload app if using multiple workers
if ENV.fetch("WEB_CONCURRENCY", 1).to_i > 1
  preload_app!
  
  # Worker forking configuration for memory efficiency
  on_worker_boot do
    # Reconnect to database after forking
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
  
  before_fork do
    # Disconnect from database before forking to avoid connection issues
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
  end
end

# Memory management settings
# Restart workers after handling a certain number of requests to prevent memory bloat
if ENV.fetch("WEB_CONCURRENCY", 1).to_i > 1
  worker_shutdown_timeout 30
  worker_timeout 30
  worker_boot_timeout 30
  
  # Restart workers that use too much memory (on platforms that support it)
  if ENV["RAILS_ENV"] == "production"
    # Restart worker if it uses more than 400MB
    worker_kill_timeout 300 # 5 minutes
  end
end

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# SolidQueue plugin - only enable if explicitly requested
# Removed automatic loading to save memory in the web process
if ENV["SOLID_QUEUE_IN_PUMA"] == "true"
  plugin :solid_queue
  
  # Configure SolidQueue to use minimal resources when running in Puma
  before_fork do
    # Reduce SolidQueue worker threads when running in web process
    ENV["SOLID_QUEUE_CONCURRENCY"] ||= "1"
  end
end

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Additional memory optimization settings
if ENV["RAILS_ENV"] == "production"
  # Set lower limits for various buffers to save memory
  queue_requests false  # Don't queue requests, handle them immediately
  
  # Reduce the maximum request size to prevent large uploads from consuming memory
  # Default is usually around 1MB, we'll keep it reasonable
  max_request_size 5 * 1024 * 1024  # 5MB max request size
  
  # Clean up completed tasks more aggressively
  nakayoshi_fork if ENV.fetch("WEB_CONCURRENCY", 1).to_i > 1
end

# Logging configuration
tag "bizblasts"
if ENV["RAILS_LOG_TO_STDOUT"].present?
  log_requests true
end
