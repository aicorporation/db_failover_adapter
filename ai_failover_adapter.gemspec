# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ai_failover_adapter/version'

Gem::Specification.new do |spec|
  spec.name          = "ai_failover_adapter"
  spec.version       = AiFailoverAdapter::VERSION
  spec.authors       = ["Adrian Hooper"]
  spec.email         = ["adrian.hooper@aicorporation.com"]
  spec.summary       = %q{Database adapter allowing peer-to-peer replication failover}
  spec.description   = %q{
    The Ai Failover Adapter allows you to setup a peer-to-peer replication
    database environment, and have your application seemlessly switch between
    connections in the event of a failure.
  }
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"

  spec.add_runtime_dependency 'activerecord', '>= 4.0.0'
end
