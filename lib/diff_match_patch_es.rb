# frozen_string_literal: true

# Diff Match and Patch
# Copyright 2018 The diff-match-patch Authors.
# https://github.com/google/diff-match-patch
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Ruby port of diff-match-patch-es (the TypeScript/ESM rewrite by Anthony Fu
# of Neil Fraser's diff-match-patch), producing identical results.
#
# The API is a set of stateless module functions; nothing mutates shared
# state, DEFAULT_OPTIONS is frozen, and every call operates only on its
# arguments and locals, so the module is safe to use from multiple threads
# (and Ractors) concurrently.
module DiffMatchPatchES
  class Error < StandardError; end
end

require_relative 'diff_match_patch_es/version'
require_relative 'diff_match_patch_es/js_string'
require_relative 'diff_match_patch_es/options'
require_relative 'diff_match_patch_es/diff'
require_relative 'diff_match_patch_es/match'
require_relative 'diff_match_patch_es/patch'

module DiffMatchPatchES
  module_function

  def diff(text1, text2, options = nil, checklines = true, deadline = nil)
    diff_main(text1, text2, options, checklines, deadline)
  end

  def match(text, pattern, loc, options = nil)
    match_main(text, pattern, loc, options)
  end

  def patch(a, opt_b = nil, opt_c = nil, options = nil)
    patch_make(a, opt_b, opt_c, options)
  end
end
