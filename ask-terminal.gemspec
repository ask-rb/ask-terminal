# frozen_string_literal: true

require_relative "lib/ask/terminal/version"

Gem::Specification.new do |spec|
  spec.name = "ask-terminal"
  spec.version = Ask::Terminal::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Terminal client for the ask session protocol"
  spec.description = "The first thin client of the ask ecosystem: an interactive terminal coding " \
                     "agent that speaks the canonical ask-session-protocol and nothing else. Spawns " \
                     "the host (ask-app-server) over stdio or attaches to a running host over its " \
                     "unix socket — the same protocol any other client (web console, bots) speaks, " \
                     "so multiple clients can share the same live sessions."

  spec.homepage = "https://github.com/ask-rb/ask-terminal"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["ask-terminal"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ask-session-protocol", ">= 0.1"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 3.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
