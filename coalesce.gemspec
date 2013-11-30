# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'coalesce/version'

Gem::Specification.new do |spec|
  spec.name          = "coalesce"
  spec.version       = Coalesce::VERSION
  spec.authors       = ["Mike Owens"]
  spec.email         = ["mike@filespanker.com"]
  spec.description   = %q{Combines objects based on rules.
                          Useful for aggregation. }
  spec.summary       = %q{Combines objects based on rules}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
