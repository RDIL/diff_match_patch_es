# Unreleased

- **Breaking:** functions that mutate an argument in place are now named with a trailing bang (`diff_cleanup_semantic!`, `diff_cleanup_efficiency!`, `diff_cleanup_merge!`, `diff_cleanup_semantic_lossless!`, `diff_chars_to_lines!`, `patch_add_context!`, `patch_add_padding!`, `patch_split_max!`).
- Optimization: Line-mode diffs split lines by byte offset.
- Optimization: Line placeholders are written and read as code points instead of one-character strings.
- Optimization: Bitap matching converts its scan window to code points once instead of indexing the text at every step.
- Optimization: `patch_make` applies pending diffs to its working text once per patch instead of recopying the text for every diff.
- Optimization: `patch_add_context!` checks whether its context is unique with a byte search on UTF-8 text.
- Optimization: Common prefix and suffix detection uses a galloping byte search, so its cost follows the shared length instead of the text length.
- Optimization: Substring extraction no longer counts the characters of the whole text first, so its cost follows the slice position instead of the text length.

# v2.0.0

- Initial release
