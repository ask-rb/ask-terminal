# frozen_string_literal: true

require_relative "test_helper"
require "socket"

class HostTest < Minitest::Test
  def teardown
    @spawned&.close
  end

  # ── Socket path resolution ─────────────────────────────────────────────

  def test_socket_path_disabled
    assert_nil Ask::Terminal::Host.send(:resolve_socket_path, false)
    assert_nil Ask::Terminal::Host.send(:resolve_socket_path, nil)
  end

  def test_socket_path_passthrough
    assert_equal "/tmp/explicit.sock", Ask::Terminal::Host.send(:resolve_socket_path, "/tmp/explicit.sock")
  end

  def test_socket_path_default_is_unique_per_spawn
    ENV["ASK_APP_SERVER_SOCKET"] = nil
    first = Ask::Terminal::Host.send(:resolve_socket_path, true)
    second = Ask::Terminal::Host.send(:resolve_socket_path, true)

    refute_equal first, second, "concurrent hosts must not share a socket path"
    assert_match(%r{\.ask-app-server/sockets/}, first)
    assert_match(/\.sock\z/, first)
  ensure
    ENV["ASK_APP_SERVER_SOCKET"] = nil
  end

  def test_socket_path_honors_env
    ENV["ASK_APP_SERVER_SOCKET"] = "/tmp/env.sock"
    assert_equal "/tmp/env.sock", Ask::Terminal::Host.send(:resolve_socket_path, true)
  ensure
    ENV["ASK_APP_SERVER_SOCKET"] = nil
  end

  # ── Spawn (needs the ask-app-server binary) ────────────────────────────

  def test_spawn_exposes_a_socket_for_attach
    skip "ask-app-server not available" unless ASK_APP_SERVER_AVAILABLE

    @spawned = Ask::Terminal::Host.spawn
    assert @spawned.socket_path, "spawned hosts should expose a socket by default"

    # Wait for the host's socket to come up, then attach like any client.
    client = connect_with_retry(@spawned.socket_path)
    result = client.initialize!
    assert_equal "ask-app-server", result.dig("server", "name")
    assert_equal "ok", client.request("ping")["status"]
  ensure
    client&.close
  end

  def test_spawn_without_socket
    skip "ask-app-server not available" unless ASK_APP_SERVER_AVAILABLE

    @spawned = Ask::Terminal::Host.spawn(socket: false)
    assert_nil @spawned.socket_path
    assert_equal "ok", @spawned.client.request("ping")["status"]
  end

  def test_spawn_with_explicit_socket_path
    skip "ask-app-server not available" unless ASK_APP_SERVER_AVAILABLE

    path = File.join(Dir.mktmpdir("ask-host-test"), "explicit.sock")
    @spawned = Ask::Terminal::Host.spawn(socket: path)
    assert_equal path, @spawned.socket_path

    client = connect_with_retry(path)
    assert_equal "ok", client.request("ping")["status"]
  ensure
    client&.close
    FileUtils.rm_rf(File.dirname(path)) if path
  end

  def test_spawned_host_removes_socket_on_close
    skip "ask-app-server not available" unless ASK_APP_SERVER_AVAILABLE

    @spawned = Ask::Terminal::Host.spawn
    connect_with_retry(@spawned.socket_path).close

    # Closing the client closes the host's stdin → the host exits and
    # removes its socket file (SocketServer#stop).
    @spawned.close
    deadline = Time.now + 3
    sleep 0.05 while File.exist?(@spawned.socket_path) && Time.now < deadline
    refute File.exist?(@spawned.socket_path), "the socket file should not outlive the host"
  end

  private

  def connect_with_retry(socket_path)
    deadline = Time.now + 5
    loop do
      return Ask::Terminal::Host.connect(socket_path)
    rescue Errno::ECONNREFUSED, Errno::ENOENT
      raise "host socket #{socket_path} not accepting" if Time.now > deadline
      sleep 0.05
    end
  end
end
