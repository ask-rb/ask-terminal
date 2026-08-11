# frozen_string_literal: true

require_relative "test_helper"
require "socket"

# End-to-end proof of the architecture: the terminal client speaks only
# the canonical session protocol, against a REAL host. The host runs
# in-process as a SocketServer (as `ask-app-server --socket` would); the
# client attaches exactly like any other client would.
class IntegrationTest < Minitest::Test
  def setup
    skip "ask-app-server not available" unless ASK_APP_SERVER_AVAILABLE

    @dir = Dir.mktmpdir("ask-terminal-test")
    @socket_path = File.join(@dir, "host.sock")
    @session_manager = Ask::AppServer::SessionManager.new
    @host = Ask::AppServer::SocketServer.new(
      session_manager: @session_manager,
      socket_path: @socket_path
    )
    @host.start
    @client = Ask::Terminal::Host.connect(@socket_path)
  end

  def teardown
    @client&.close
    @host&.stop
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_handshake_negotiates_protocol
    result = @client.initialize!
    assert_equal "ask-app-server", result.dig("server", "name")
    assert_equal Ask::SessionProtocol::PROTOCOL_VERSION, result["protocolVersion"]
  end

  def test_full_session_lifecycle_over_socket
    @client.initialize!
    created = @client.create_session(workspace_path: "/tmp", mode: "on_request")
    session_id = created.dig("session", "sessionId")
    assert session_id

    @client.subscribe(session_id, after_seq: 0)

    sent = @client.send(session_id, "Hello")
    assert_equal "steered", sent["status"]

    closed = @client.close_session(session_id)
    assert closed["closed"]
  end

  def test_approval_events_stream_to_the_client
    @client.initialize!
    created = @client.create_session(workspace_path: "/tmp", mode: "on_request")
    session_id = created.dig("session", "sessionId")
    @client.subscribe(session_id, after_seq: 0)

    # The host's real approval queue emits approval.required through the
    # canonical pipeline (queue → translator → session log → push).
    queue = @session_manager.get(session_id).session.approval_queue
    queue.submit(tool_call_id: "call-1", tool_name: "bash", args: { "command" => "ls" }, message: "test")

    event = wait_for_event("approval.required", client: @client)
    assert_equal "act_1", event.dig("payload", "id")
    assert_equal "bash", event.dig("payload", "toolName")
  end

  def test_two_clients_share_the_same_session
    @client.initialize!
    created = @client.create_session(workspace_path: "/tmp", mode: "on_request")
    session_id = created.dig("session", "sessionId")
    @client.subscribe(session_id, after_seq: 0)

    second = Ask::Terminal::Host.connect(@socket_path)
    second.initialize!
    second.subscribe(session_id, after_seq: 0)

    queue = @session_manager.get(session_id).session.approval_queue
    queue.submit(tool_call_id: "call-1", tool_name: "bash")

    @host.protocol.push_pending

    first_event = wait_for_event("approval.required", client: @client)
    second_event = wait_for_event("approval.required", client: second)

    assert_equal "approval.required", first_event["type"]
    assert_equal "approval.required", second_event["type"]
  ensure
    second&.close
  end

  private

  # Drain notifications until an event of the given type arrives (the
  # subscription replays session.created first).
  def wait_for_event(type, client:, timeout: 3)
    deadline = Time.now + timeout
    loop do
      notification = client.wait_notification(timeout: 0.2)
      flunk "timed out waiting for #{type}" if notification.nil? && Time.now > deadline

      event = notification&.dig("params", "event")
      return event if event && event["type"] == type
    end
  end
end
