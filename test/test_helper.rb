# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    track_files "lib/**/*.rb"
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ask-terminal"

require "json"
require "stringio"
require "tmpdir"

require "minitest/autorun"
begin
  require "mocha/minitest"
rescue LoadError
  # mocha is a dev dependency; without it, stubs are unavailable but the
  # non-mocking tests still run (e.g. plain `ruby -Ilib -Itest`).
end

# The ask-app-server host is only needed for integration tests. Under the
# monorepo Gemfile it resolves via path; in a standalone checkout the tests
# skip when it is absent.
begin
  require "ask-app-server"
  ASK_APP_SERVER_AVAILABLE = true
rescue LoadError
  ASK_APP_SERVER_AVAILABLE = false
end
