Gem::Specification.new do |spec|
  spec.name = "kryptic-daemon"
  spec.version = "0.1.0"
  spec.authors = ["Kryptic"]
  spec.summary = "Kryptic daemon client for Ruby. Passively injects development secrets from the local Kryptic daemon into ENV."
  spec.description = "During development startup, Kryptic.inject! fetches the current project's secrets " \
                     "from the local Kryptic daemon and puts them into ENV. No-op outside development."
  spec.homepage = "https://kryptic.dev"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 2.6"
  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]
end
