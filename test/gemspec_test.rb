# frozen_string_literal: true

require_relative "test_helper"

class GemspecTest < Minitest::Test
  def test_gemspec_is_valid
    spec = Gem::Specification.load("ask-terminal.gemspec")
    assert spec, "gemspec should load"
    assert_equal "ask-terminal", spec.name
    assert_equal Ask::Terminal::VERSION, spec.version.to_s
    assert spec.summary, "should have a summary"
    assert spec.description, "should have a description"
    assert spec.homepage, "should have a homepage"
    assert_equal "MIT", spec.license
    assert spec.files.any? { |f| f.start_with?("lib/") }, "should include lib files"
    assert_includes spec.executables, "ask-terminal", "should have ask-terminal executable"
    assert_includes spec.files, "LICENSE", "should include LICENSE"
  end

  def test_version_is_defined
    assert_equal "0.2.0", Ask::Terminal::VERSION
  end

  def test_depends_on_session_protocol
    spec = Gem::Specification.load("ask-terminal.gemspec")
    assert spec.dependencies.any? { |d| d.name == "ask-session-protocol" }
  end

  def test_ships_both_executables
    spec = Gem::Specification.load("ask-terminal.gemspec")
    assert_includes spec.executables, "ask", "the short command is primary"
    assert_includes spec.executables, "ask-terminal", "the long name remains an alias"
  end

  def test_executables_exist_and_are_executable
    %w[ask ask-terminal].each do |name|
      path = File.expand_path("../exe/#{name}", __dir__)
      assert File.exist?(path), "exe/#{name} should exist"
      assert File.executable?(path), "exe/#{name} should be executable"
    end
  end
end
