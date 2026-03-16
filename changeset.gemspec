$:.push File.expand_path("lib", __dir__)

require "changeset/version"

Gem::Specification.new do |spec|
  spec.name = "changeset"
  spec.version = Changeset::VERSION
  spec.authors = ["Benjamin Roth"]
  spec.email = ["benjamin@rubyist.fr"]
  spec.summary = "Unit-of-work with event dispatch for Rails"
  spec.description = "Collect DB operations and events, execute in one transaction, dispatch events after commit."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["{lib,rbi}/**/*", "MIT-LICENSE", "README.md"]

  spec.add_dependency "zeitwerk", ">= 2.5"
end
