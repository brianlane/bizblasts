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
# Memory-optimized configuration for Render 512MB plan
# Reduced thread count to minimize memory usage
# Each thread typically uses 8-32MB of memory
threads_count = ENV.fetch("RAILS_MAX_THREADS") do
  # Use fewer threads on production to conserve memory
  Rails.env.production? ? 2 : 3
end
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
# Only use one port binding method to avoid conflicts
port ENV.fetch("PORT", 3000)

# Preload the application for memory efficiency
if Rails.env.production?
  preload_app!
  
  # Memory optimization settings
  worker_timeout 60
  worker_shutdown_timeout 30
  
  # Force garbage collection before forking workers
  before_fork do
    GC.start(full_mark: true, immediate_sweep: true)
  end
end

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
# Only in production to avoid memory overhead in development
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] && Rails.env.production?

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Memory monitoring and cleanup
if Rails.env.production?
  # Log memory usage periodically
  lowlevel_error_handler do |ex, env|
    memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    puts "[Memory Alert] Process memory: #{memory_mb}MB during error: #{ex.message}"
    [500, {}, ["Internal Server Error"]]
  end
end
