# v3.0.1

(Re-publish of 3.0.0 due to broken Rakefile. No code changes.)

# v3.0.0

- **Breaking:** functions that mutate an argument in place are now named with a trailing bang (`diff_cleanup_semantic!`, `diff_cleanup_efficiency!`, `diff_cleanup_merge!`, `diff_cleanup_semantic_lossless!`, `diff_chars_to_lines!`, `patch_add_context!`, `patch_add_padding!`, `patch_split_max!`).
- Fix: Matching in ASCII-only or valid UTF-8 text no longer goes through `String#rindex`, which can read past the end of the text and crash the interpreter ([Ruby bug #22548](https://bugs.ruby-lang.org/issues/22548)).
- Fix: Semantic cleanup no longer treats `ſ` (U+017F) and `K` (U+212A) as alphanumeric, which the JavaScript library does not.
- Feature: `Options` defines `eql?` and `hash`, so equal options are the same Hash key and are deduplicated by `uniq`.
- Optimization: Line-mode diffs split lines by byte offset.
- Optimization: Line placeholders are written and read as code points instead of one-character strings.
- Optimization: Bitap matching converts its scan window to code points once instead of indexing the text at every step.
- Optimization: `patch_make` applies pending diffs to its working text once per patch instead of recopying the text for every diff.
- Optimization: `patch_add_context!` checks whether its context is unique with a byte search on UTF-8 text.
- Optimization: Common prefix and suffix detection uses a galloping byte search, so its cost follows the shared length instead of the text length.
- Optimization: Substring extraction no longer counts the characters of the whole text first, so its cost follows the slice position instead of the text length.
- Optimization: Substring search from an offset in multi-byte text slices off the tail instead of walking to the offset one character at a time, and a search from the start no longer counts the characters of the text.
- Optimization: Backward substring search in valid UTF-8 text is a byte search instead of a walk to its start one character at a time.
- Optimization: `patch_to_text` and `diff_to_delta` escape text in one pass over runs of escaped characters instead of testing and appending one character at a time.
- Optimization: `patch_from_text` and `diff_from_delta` unescape text in two passes over its escapes instead of walking it one character at a time, which was quadratic for non-ASCII text.
- Optimization: Bitap matching looks for an exact match before the expected location only as far back as the nearest one after it, instead of through all of the preceding text.
- Optimization: Character-level diffs follow long runs of equal characters by comparing blocks of them instead of one character at a time.

# v2.0.0

- Initial release
