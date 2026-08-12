# frozen_string_literal: true

require_relative "test_helper"

class CliTest < Minitest::Test
  def test_command_name_is_short
    assert_equal "ask", Ask::Terminal::CLI::COMMAND_NAME
  end

  def test_help_prints_usage_and_exits_zero
    out, err = capture_io do
      status = Ask::Terminal::CLI.run!(["--help"])
      assert_equal 0, status
    end
    assert_includes out, "Usage: ask [options]"
  end

  def test_run_requires_socket_path_in_attach_mode
    out, err = capture_io do
      assert_raises(SystemExit) do
        Ask::Terminal::CLI.run!(["--host", "socket"])
      end
    end
    assert_match(/socket path is required/, err)
  end
end
