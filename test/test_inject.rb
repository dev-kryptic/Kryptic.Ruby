# Tests against a mock daemon: a unix-socket server speaking PROTOCOL.md v1.
require "minitest/autorun"
require "json"
require "socket"
require "tmpdir"
require "fileutils"

require_relative "../lib/kryptic"

class InjectTest < Minitest::Test
  def setup
    @project_dir = Dir.mktmpdir
    File.write(File.join(@project_dir, "kryptic.json"), JSON.generate(projectId: "proj_test123456"))
    @old_cwd = Dir.pwd
    Dir.chdir(@project_dir)

    %w[KRYPTIC_DISABLED KRYPTIC_PROJECT_ID KRYPTIC_ENV RAILS_ENV INJECTED_KEY EXISTING_KEY].each { |k| ENV.delete(k) }
    ENV["KRYPTIC_SILENT"] = "true"
    @server = nil
  end

  def teardown
    Dir.chdir(@old_cwd)
    @server&.close
    ENV.delete("KRYPTIC_SOCKET_PATH")
    FileUtils.remove_entry(@project_dir)
    FileUtils.remove_entry(@socket_dir) if @socket_dir
  end

  def start_mock_daemon(&handler)
    # Unix socket paths are length-capped; keep them short under /tmp.
    @socket_dir = Dir.mktmpdir("kd", "/tmp")
    path = File.join(@socket_dir, "d.sock")
    @server = UNIXServer.new(path)
    ENV["KRYPTIC_SOCKET_PATH"] = path

    Thread.new do
      loop do
        connection = @server.accept
        request = JSON.parse(connection.gets("\n"))
        connection.write(JSON.generate(handler.call(request)) + "\n")
        connection.close
      rescue StandardError
        break
      end
    end
  end

  def test_injects_secrets_into_env
    seen = nil
    start_mock_daemon do |request|
      seen = request
      { v: 1, ok: true, secrets: [{ key: "INJECTED_KEY", value: "from-daemon" }] }
    end

    result = Kryptic.inject!

    refute result.skipped
    assert_equal 1, result.injected
    assert_equal "from-daemon", ENV["INJECTED_KEY"]
    assert_equal "proj_test123456", seen["projectId"]
    assert_equal "development", seen["environment"]
  end

  def test_never_overwrites_existing_variables
    ENV["EXISTING_KEY"] = "real-env-wins"
    start_mock_daemon { { v: 1, ok: true, secrets: [{ key: "EXISTING_KEY", value: "x" }] } }

    result = Kryptic.inject!

    assert_equal 0, result.injected
    assert_equal "real-env-wins", ENV["EXISTING_KEY"]
  end

  def test_noop_when_daemon_missing
    ENV["KRYPTIC_SOCKET_PATH"] = File.join(@project_dir, "missing.sock")

    result = Kryptic.inject!

    assert result.skipped
    assert_equal "daemon_unreachable", result.reason
  end

  def test_noop_in_production
    ENV["RAILS_ENV"] = "production"

    result = Kryptic.inject!

    assert result.skipped
    assert_equal "rails_env_production", result.reason
  end

  def test_noop_when_disabled
    ENV["KRYPTIC_DISABLED"] = "true"

    result = Kryptic.inject!

    assert result.skipped
    assert_equal "disabled", result.reason
  end

  def test_handles_error_responses
    start_mock_daemon { { v: 1, ok: false, error: "access_denied" } }

    result = Kryptic.inject!

    assert result.skipped
    assert_equal "access_denied", result.reason
  end

  def test_env_overrides_win
    ENV["KRYPTIC_PROJECT_ID"] = "proj_override0001"
    ENV["KRYPTIC_ENV"] = "staging"
    seen = nil
    start_mock_daemon do |request|
      seen = request
      { v: 1, ok: true, secrets: [] }
    end

    Kryptic.inject!

    assert_equal "proj_override0001", seen["projectId"]
    assert_equal "staging", seen["environment"]
  end
end
