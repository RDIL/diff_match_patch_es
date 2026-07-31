# frozen_string_literal: true

require_relative 'lib/diff_match_patch_es/version'

Gem::Specification.new do |spec|
  spec.name = 'diff_match_patch_es'
  spec.version = DiffMatchPatchES::VERSION
  spec.authors = ['Neil Fraser', 'Anthony Fu', 'Reece Dunham']
  spec.summary = 'Thread-safe Ruby port of diff-match-patch-es'
  spec.description = 'Diff Match and Patch as stateless, thread-safe module functions, ' \
                     'ported from the diff-match-patch-es TypeScript rewrite and ' \
                     'producing identical results.'
  spec.homepage = 'https://github.com/RDIL/diff_match_patch_es'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.3'

  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs', 'README.md']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
