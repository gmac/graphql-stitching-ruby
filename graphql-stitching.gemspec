# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'graphql/stitching/version'

Gem::Specification.new do |spec|
  spec.name          = 'graphql-stitching'
  spec.version       = GraphQL::Stitching::VERSION
  spec.authors       = ['Greg MacWilliam']
  spec.summary       = 'GraphQL schema stitching for Ruby'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/gmac/graphql-stitching-ruby'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.1.1'

  spec.metadata    = {
    'homepage_uri' => 'https://github.com/gmac/graphql-stitching-ruby',
    'changelog_uri' => 'https://github.com/gmac/graphql-stitching-ruby/releases',
    'source_code_uri' => 'https://github.com/gmac/graphql-stitching-ruby',
    'bug_tracker_uri' => 'https://github.com/gmac/graphql-stitching-ruby/issues',
  }

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^test/})
  end
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'graphql', '~> 2.0.16'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'minitest', '~> 5.12'
end
