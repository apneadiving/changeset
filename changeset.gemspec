$:.push File.expand_path("lib", __dir__)

require "changeset/version"

Gem::Specification.new do |spec|
  spec.name = "changeset"
  spec.version = Changeset::VERSION
  spec.authors = ["Benjamin Roth"]
  spec.email = ["benjamin@rubyist.fr"]
  spec.summary = "Propagate persistence and events from actions"
  spec.description = "Propagate persistence and events from actions"
  spec.license = "MIT"

  spec.files = Dir["{lib,rbi}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "zeitwerk"
end
