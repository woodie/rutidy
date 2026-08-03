# frozen_string_literal: true

require_relative "lib/rutidy/version"

Gem::Specification.new do |spec|
  spec.name = "rutidy"
  spec.version = Rutidy::VERSION
  spec.authors = ["John Woodell"]
  spec.email = ["woodie@netpress.com"]

  spec.summary = "RSpec/Mocha/Vitest-style output for RSpec"
  spec.description = "A real RSpec formatter plus a small renderer that turns RSpec's " \
                      "own example tree into the same classic/fd/fs/fv styles gorderly, " \
                      "kotidy, and xctidy already share."
  spec.homepage = "https://github.com/woodie/rutidy"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # standard/rubocop live in the Gemfile's :lint group, not here -- rubocop's
  # own dependency chain (parallel, currently) moves its required_ruby_version
  # floor forward faster than this gem's own runtime code does, and lint
  # tooling never ships to users, so it shouldn't force every supported Ruby
  # version to also satisfy rubocop's floor. See docs/COWORK.md.
  spec.add_development_dependency "rspec", "~> 3.13"
end
