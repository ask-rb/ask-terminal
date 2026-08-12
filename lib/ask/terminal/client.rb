# frozen_string_literal: true

# The protocol client moved to the ask-session-client gem; this constant
# is kept as an alias so existing references keep working.
require "ask-session-client"

Ask::Terminal::Client = Ask::SessionClient::Client
