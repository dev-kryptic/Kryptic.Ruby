# krypticdev (Ruby SDK)

```ruby
# Gemfile
gem "krypticdev", group: :development

# config/application.rb
require "krypticdev"
Kryptic.inject! if Rails.env.development?
```

Fetches the project's secrets from the local Kryptic daemon into ENV during development.
No-op outside development (RAILS_ENV/RACK_ENV/APP_ENV = production/staging, or
KRYPTIC_DISABLED=true). Never raises; never overwrites existing ENV values.
Configuration: KRYPTIC_PROJECT_ID, KRYPTIC_ENV, KRYPTIC_SOCKET_PATH, KRYPTIC_TIMEOUT_MS, KRYPTIC_SILENT.

Protocol: [daemon/PROTOCOL.md](https://github.com/dev-kryptic/Kryptic.Daemon/blob/main/PROTOCOL.md). License: Apache-2.0. `ruby test/test_inject.rb`
