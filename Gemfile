source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Declare your gem's dependencies in flow.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

# To use a debugger
# gem 'byebug', group: [:development, :test]
gem "sorbet-runtime", "0.5.10473"

group :development, :test do
  gem "sorbet", "0.5.10473"
  gem "tapioca", require: false
  gem "standard"
end

group :test do
  gem "rspec", "3.11.0"
  gem "byebug"
end
