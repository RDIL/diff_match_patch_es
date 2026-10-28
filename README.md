# diff_match_patch_es (Ruby)

A thread-safe Ruby port of [diff-match-patch-es](https://github.com/antfu/diff-match-patch-es) (the TypeScript/ESM rewrite of Google's [diff-match-patch](https://github.com/google/diff-match-patch)), producing results identical to the JavaScript implementation.

## Usage

```ruby
require 'diff_match_patch_es'

diffs = DiffMatchPatchES.diff_main('Apples are a fruit.', 'Bananas are also fruit.')
# => [[-1, "Apple"], [1, "Banana"], [0, "s are a"], [1, "lso"], [0, " fruit."]]

diffs = DiffMatchPatchES.diff_main('mouse', 'sofas')
DiffMatchPatchES.diff_cleanup_semantic!(diffs)
diffs # => [[-1, "mouse"], [1, "sofas"]]

patches = DiffMatchPatchES.patch_make('The quick brown fox.', 'The slow green fox.')
text = DiffMatchPatchES.patch_to_text(patches)
DiffMatchPatchES.patch_apply(DiffMatchPatchES.patch_from_text(text), 'The quick brown fox.')
# => ["The slow green fox.", [true]]

DiffMatchPatchES.match_main('abcdefghijk', 'fgh', 5) # => 5
```

Every exported function of the JS package has a snake_case equivalent (`diffMain` -> `diff_main`, `patchApply` -> `patch_apply`, …), plus the short aliases `diff`, `match`, and `patch`.
Functions that mutate an argument in place additionally end in a bang: `diff_cleanup_semantic!`, `diff_cleanup_efficiency!`, `diff_cleanup_merge!`, `diff_cleanup_semantic_lossless!`, `diff_chars_to_lines!`, `patch_add_context!`, `patch_add_padding!`, and `patch_split_max!`.
Diffs are `[op, text]` arrays with the ops `DIFF_DELETE` (-1), `DIFF_EQUAL` (0), and `DIFF_INSERT` (1); patches are `DiffMatchPatchES::Patch` objects whose `#to_s` emits the GNU-diff-style  format.

Options are passed as a trailing hash (or a resolved `DiffMatchPatchES::Options`), mirroring the JS option names:

```ruby
DiffMatchPatchES.diff_main(a, b, { diff_timeout: 0, diff_edit_cost: 4 })
DiffMatchPatchES.match_main(text, pattern, loc, { match_threshold: 0.4, match_distance: 100 })
```

## Type signatures

Full RBS signatures for the public API (and internal helpers) ship with the gem under `sig/`, so Steep/TypeProf/`rbs` pick them up automatically.
Diffs are typed as `[op, String]` tuples where `op` is the literal union `-1 | 0 | 1`, and every `patch_make` call format is covered by an overload.

## Thread/Ractor safety

The entire API is stateless module functions: no globals are mutated, all constants (including `DEFAULT_OPTIONS`) are frozen, and every call operates only on its arguments and locals.
Calling any function from multiple threads (or Ractors) concurrently is safe!
The only caveat is the obvious one: don't mutate a single `Options` instance or a shared diffs array from two threads at the same time.

## Parity with the JavaScript implementation

The port is verified two ways:

- The upstream vitest suite is ported 1:1 to minitest (`test/`).
- A cross-language parity suite (`parity/`) runs a static corpus of 404 cases (`parity/cases.json` — committed, human-readable) through both the published npm package (pinned by `parity/yarn.lock`) and this port, and asserts byte-identical output for every public function (diffs, cleanups, deltas, patch text, patch apply, match):

  ```sh
  bundle exec rake parity
  ```

  Requires Node with corepack enabled (the JS side is installed with Yarn via
  the `packageManager` pin). CI runs this on every push. The corpus was
  generated once with `node parity/gen_cases.mjs` (seeded PRNG plus
  hand-picked edge cases); rerun that script to regenerate or expand it.

JS-specific semantics are reproduced deliberately, including `substring`
clamping, `encodeURI`/`decodeURI` behavior (reserved `%XX` escapes are left
intact; malformed UTF-8 raises), `parseInt` prefix parsing, 32-bit bitwise
arithmetic in the Bitap matcher, and the sparse-array behavior of the
semantic cleanup's equalities stack.

**Known divergence:** JavaScript strings are UTF-16 code units, so on
supplementary-plane input (emoji, some CJK extensions) the JS implementation
may split surrogate pairs and emit lone surrogates, e.g.
`diffMain('🍏x', '🍎x')` → `[[0,'\ud83c'],[-1,'\udf4f'],[1,'\udf4e'],[0,'x']]`.
Lone surrogates cannot exist in UTF-8, so the Ruby port operates on whole
characters and returns `[[-1,'🍏'],[1,'🍎'],[0,'x']]` — same edit, valid
strings. For all text within the Basic Multilingual Plane the outputs are
identical.

`diff_timeout` (default 1 second) cuts the search off at a wall-clock
deadline, so under timeout pressure any two runs — in either language — can
legitimately differ; pass `diff_timeout: 0` for deterministic (slower)
results.

## Tests

```sh
rake test
```

## Credits

- Neil Fraser for the implementation that started it all
- Anthony Fu for the TypeScript/ESM rewrite that allowed this to be a significantly easier process 
