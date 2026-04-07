# frozen_string_literal: true

require_relative "lib/call_coding_clis/version"

Gem::Specification.new do |spec|
  spec.name          = "call_coding_clis"
  spec.version       = CallCodingClis::VERSION
  spec.summary       = "Library and CLI for invoking coding CLIs as subprocesses"
  spec.authors       = ["call-coding-clis contributors"]
  spec.license       = "Unlicense"

  spec.files         = Dir.glob("lib/**/*") + Dir.glob("bin/*")
  spec.executables   = ["ccc"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.6"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
