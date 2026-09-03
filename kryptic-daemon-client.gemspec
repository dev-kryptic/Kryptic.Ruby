Gem::Specification.new do |spec|
  spec.name = "kryptic-daemon-client"
  spec.version = "0.1.5"
  spec.authors = ["Kryptic"]
  spec.summary = "Kryptic daemon client for Ruby. Passively injects development secrets from the local Kryptic daemon into ENV."
  spec.description = "During development startup, Kryptic.inject! fetches the current project's secrets " \
                     "from the local Kryptic daemon and puts them into ENV. No-op outside development."
  spec.homepage = "https://kryptic.dev"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 2.6"
  spec.metadata = {
    "homepage_uri" => "https://kryptic.dev",
    "source_code_uri" => "https://github.com/dev-kryptic/Kryptic.Ruby",
    "bug_tracker_uri" => "https://github.com/dev-kryptic/Kryptic.Ruby/issues",
    "allowed_push_host" => "https://rubygems.org",
  }
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
