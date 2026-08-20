# The Kryptic daemon client for Ruby. During development startup, Kryptic.inject! fetches the
# current project's secrets from the local Kryptic daemon and puts them into ENV.
# Outside development it is a no-op. It never raises; a missing daemon means the
# application simply starts with whatever environment it already has.
#
# Protocol: daemon/PROTOCOL.md v1 (newline-delimited JSON over a local socket,
# a unix domain socket on macOS/Linux, a named pipe on Windows).

require "json"
require "socket"
require "timeout"

module Kryptic
  PROTOCOL_VERSION = 1

  Result = Struct.new(:injected, :skipped, :reason, keyword_init: true)

  module_function

  # Call before the app reads ENV, e.g. in config/application.rb:
  #   Kryptic.inject! if Rails.env.development?
  def inject!(environment: nil, project_id: nil, timeout_ms: nil)
    reason = skip_reason
    return Result.new(injected: 0, skipped: true, reason: reason) if reason

    config = find_kryptic_json

    project_id ||= ENV["KRYPTIC_PROJECT_ID"] || config&.fetch("projectId", nil)
    unless project_id
      warn_once "no kryptic.json found (and no KRYPTIC_PROJECT_ID set) - nothing to inject."
      return Result.new(injected: 0, skipped: true, reason: "no_project")
    end

    environment ||= ENV["KRYPTIC_ENV"] || config&.fetch("defaultEnvironment", nil) || "development"
    timeout_ms ||= (ENV["KRYPTIC_TIMEOUT_MS"] || 2000).to_i

    begin
      response = request(project_id, environment, timeout_ms / 1000.0)
    rescue StandardError => e
      warn_once "daemon not reachable (#{e.class}: #{e.message}) - continuing without injected secrets."
      return Result.new(injected: 0, skipped: true, reason: "daemon_unreachable")
    end

    unless response["ok"]
      error = response["error"] || "internal"
      warn_once "daemon refused the request (#{error}): #{response["message"]}"
      return Result.new(injected: 0, skipped: true, reason: error)
    end

    injected = 0
    (response["secrets"] || []).each do |secret|
      key = secret["key"]
      next if key.nil? || key.empty? || ENV.key?(key) # real environment always wins

      ENV[key] = secret["value"].to_s
      injected += 1
    end

    Result.new(injected: injected, skipped: false)
  end

  def skip_reason
    return "disabled" if ENV["KRYPTIC_DISABLED"] == "true"

    # Rails/Rack conventions first, then the generic ones.
    %w[RAILS_ENV RACK_ENV APP_ENV ENVIRONMENT].each do |variable|
      value = ENV[variable].to_s.downcase
      return "#{variable.downcase}_#{value}" if %w[production prod staging].include?(value)
    end

    nil
  end

  def socket_path
    return ENV["KRYPTIC_SOCKET_PATH"] if ENV["KRYPTIC_SOCKET_PATH"]

    return '\\\\.\\pipe\\kryptic-daemon' if windows?

    if RUBY_PLATFORM.include?("linux") && ENV["XDG_RUNTIME_DIR"]
      return File.join(ENV["XDG_RUNTIME_DIR"], "kryptic-daemon.sock")
    end

    "/tmp/kryptic-daemon.sock"
  end

  def windows?
    RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)
  end

  def request(project_id, environment, timeout_seconds)
    payload = { v: PROTOCOL_VERSION, type: "secrets", projectId: project_id, environment: environment }
    line = JSON.generate(payload) + "\n"
    path = socket_path

    if windows? && path.start_with?('\\\\.\\pipe\\')
      JSON.parse(round_trip_named_pipe(path, line, timeout_seconds))
    else
      Timeout.timeout(timeout_seconds) do
        UNIXSocket.open(path) do |socket|
          socket.write(line)
          socket.gets("\n").then { |raw| JSON.parse(raw) }
        end
      end
    end
  end

  # The daemon serves a byte-mode named pipe, so a plain file handle works.
  # The timeout covers connecting (the pipe can briefly report "busy" between
  # served clients); the read then blocks until the daemon replies, which it
  # does immediately or not at all; matching the .NET client's semantics.
  def round_trip_named_pipe(path, line, timeout_seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
    pipe = nil
    begin
      pipe = File.open(path, "r+b")
    rescue SystemCallError
      raise IOError, "timed out connecting to the daemon pipe" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
      retry
    end

    begin
      pipe.write(line)
      pipe.flush
      response = pipe.gets("\n")
      raise IOError, "connection closed" unless response

      response
    ensure
      pipe.close
    end
  end

  # Walks up from the working directory looking for kryptic.json.
  def find_kryptic_json
    directory = Dir.pwd
    loop do
      candidate = File.join(directory, "kryptic.json")
      if File.file?(candidate)
        begin
          return JSON.parse(File.read(candidate))
        rescue JSON::ParserError
          warn_once "could not parse #{candidate} - ignoring it."
          return nil
        end
      end
      parent = File.dirname(directory)
      return nil if parent == directory

      directory = parent
    end
  end

  def warn_once(message)
    return if ENV["KRYPTIC_SILENT"] == "true"

    warn "[kryptic] #{message}"
  end
end
