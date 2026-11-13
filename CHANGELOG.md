# Unreleased

- **Breaking:** functions that mutate an argument in place are now named with a trailing bang (`diff_cleanup_semantic!`, `diff_cleanup_efficiency!`, `diff_cleanup_merge!`, `diff_cleanup_semantic_lossless!`, `diff_chars_to_lines!`, `patch_add_context!`, `patch_add_padding!`, `patch_split_max!`).
- Optimization: Line-mode diffs split lines by byte offset.
- Optimization: Line placeholders are written and read as code points instead of one-character strings.

# v2.0.0

- Initial release
