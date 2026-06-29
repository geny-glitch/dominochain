# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# to prioritize throughput over latency.
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

# Puma's default is to wait forever for worker threads during graceful shutdown. If any thread
# is stuck in app code (or blocked outside Puma's force-shutdown wrapper), Ctrl+C and
# SIGTERM never finish. Cap wait time; override with PUMA_FORCE_SHUTDOWN_AFTER (seconds),
# or set to "forever" for the previous behavior.
# Note: `ENV.fetch("PUMA_FORCE_SHUTDOWN_AFTER", "15")` keeps "" if the key is set but empty
# (e.g. in .env), which would incorrectly map to :forever — normalize blanks to the default.
force_shutdown_after(
  begin
    v = ENV["PUMA_FORCE_SHUTDOWN_AFTER"].to_s.strip.downcase
    v = "15" if v.empty?
    case v
    when "forever" then :forever
    when "immediately" then :immediately
    else Float(v)
    end
  end
)

# iTerm (and some other terminals) occasionally leave SIGINT not reaching Puma, or graceful
# stop feels wedged. After boot, wrap SIGINT: first interrupt logs and uses Puma's handler;
# a second within 3s calls halt (immediate teardown via Puma.stats_object → launcher).
development = (ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development") == "development"
if development
  first_int_deadline = nil
  after_booted do
    $stderr.sync = true
    # If you never see the "interrupt received" line when pressing Ctrl+C, the signal is not
    # reaching this Ruby process (shell still owns the TTY session). Use kill -INT, or start with
    # `exec bin/rails s` so the server replaces the shell and Ctrl+C targets Puma.
    warn "[Puma] Stop if Ctrl+C fails: kill -INT #{Process.pid}  |  reliable Ctrl+C: exec bin/rails s"
    previous = Signal.trap("INT") do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if first_int_deadline && now <= first_int_deadline
        warn "\n[Puma] second interrupt — halting immediately (PID #{Process.pid})"
        runner = Puma.stats_object
        runner&.instance_variable_get(:@launcher)&.halt
      else
        first_int_deadline = now + 3
        warn "\n[Puma] interrupt received — graceful stop (interrupt again within 3s to force quit; or: kill -INT #{Process.pid})"
        previous.call if previous.respond_to?(:call)
      end
    end
  end
end

# Bind to all interfaces (0.0.0.0) so Fly.io and Android emulator can reach the server.
# Fly.io requires binding to 0.0.0.0, not localhost/127.0.0.1.
bind "tcp://0.0.0.0:#{ENV.fetch("PORT", 3000)}"

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run Solid Queue inside Puma when SOLID_QUEUE_IN_PUMA is set (local dev convenience).
# Production/staging use a dedicated `worker` Fly process (`bin/jobs`) instead.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
