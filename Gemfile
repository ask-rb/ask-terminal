# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :test do
  gem "minitest", "~> 5.25"
  gem "mocha", "~> 3.1"
  gem "rake", "~> 13.0"
  gem "simplecov", "~> 0.22"
end

# Local development against sibling gems (ask-rb monorepo). Only active when
# the siblings are present; in a standalone checkout (CI) the published gems
# declared in the gemspec are used instead.
monorepo = Dir.exist?(File.expand_path("../ask-session-protocol", __dir__))
if monorepo
  gem "ask-session-protocol", path: "../ask-session-protocol"
  gem "ask-session-client", path: "../ask-session-client"
  gem "ask-app-server", path: "../ask-app-server"
end
