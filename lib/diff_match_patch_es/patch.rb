# frozen_string_literal: true

module DiffMatchPatchES
  # One patch operation.
  class Patch
    attr_accessor :diffs, :start1, :start2, :length1, :length2

    def initialize
      @diffs = []
      @start1 = nil
      @start2 = nil
      @length1 = 0
      @length2 = 0
    end

    # Emulate GNU diff's format.
    # Header: @@ -382,8 +481,9 @@
    # Indices are printed as 1-based, not 0-based.
    def to_s
      coords1 = if length1.zero?
                  "#{start1},0"
                elsif length1 == 1
                  (start1 + 1).to_s
                else
                  "#{start1 + 1},#{length1}"
                end
      coords2 = if length2.zero?
                  "#{start2},0"
                elsif length2 == 1
                  (start2 + 1).to_s
                else
                  "#{start2 + 1},#{length2}"
                end

      text = +"@@ -#{coords1} +#{coords2} @@\n"
      # Escape the body of the patch with %xx notation.
      diffs.each do |(op, data)|
        sign = case op
               when DIFF_INSERT then '+'
               when DIFF_DELETE then '-'
               when DIFF_EQUAL then ' '
               end
        text << sign << JsString.encode_uri(data) << "\n"
      end
      text.gsub('%20', ' ')
    end

    def ==(other)
      other.is_a?(Patch) &&
        diffs == other.diffs &&
        start1 == other.start1 &&
        start2 == other.start2 &&
        length1 == other.length1 &&
        length2 == other.length2
    end
  end

  module_function

  def create_patch
    Patch.new
  end

  # Increase the context until it is unique,
  # but don't let the pattern expand beyond match_max_bits.
  def patch_add_context(patch, text, options)
    return if text.empty?

    raise Error, 'patch not initialized' if patch.start2.nil?

    resolved = resolve_options(options)
    match_max_bits = resolved.match_max_bits
    patch_margin = resolved.patch_margin

    pattern = JsString.substring(text, patch.start2, patch.start2 + patch.length1)
    padding = 0

    # Look for the first and last matches of pattern in text.  If two
    # different matches are found, increase the pattern length.
    while JsString.index_of(text, pattern) != JsString.last_index_of(text, pattern, text.length) &&
          pattern.length < match_max_bits - patch_margin - patch_margin
      padding += patch_margin
      pattern = JsString.substring(text, patch.start2 - padding, patch.start2 + patch.length1 + padding)
    end
    # Add one chunk for good luck.
    padding += patch_margin

    # Add the prefix.
    prefix = JsString.substring(text, patch.start2 - padding, patch.start2)
    patch.diffs.unshift(create_diff(DIFF_EQUAL, prefix)) unless prefix.empty?

    # Add the suffix.
    suffix = JsString.substring(text, patch.start2 + patch.length1, patch.start2 + patch.length1 + padding)
    patch.diffs.push(create_diff(DIFF_EQUAL, suffix)) unless suffix.empty?

    # Roll back the start points.
    patch.start1 -= prefix.length
    patch.start2 -= prefix.length
    # Extend the lengths.
    patch.length1 += prefix.length + suffix.length
    patch.length2 += prefix.length + suffix.length
    nil
  end

  # Compute a list of patches to turn text1 into text2.
  # Use diffs if provided, otherwise compute it ourselves.
  # There are four ways to call this function, depending on what data is
  # available to the caller:
  # Method 1: a = text1, b = text2
  # Method 2: a = diffs
  # Method 3 (optimal): a = text1, b = diffs
  # Method 4 (deprecated, use method 3): a = text1, b = text2, c = diffs
  def patch_make(a, opt_b = nil, opt_c = nil, options = nil)
    resolved = resolve_options(options)

    if a.is_a?(String) && opt_b.is_a?(String) && opt_c.nil?
      # Method 1: text1, text2
      # Compute diffs from text1 and text2.
      text1 = a
      diffs = diff_main(text1, opt_b, resolved, true)
      if diffs.length > 2
        diff_cleanup_semantic(diffs)
        diff_cleanup_efficiency(diffs, resolved)
      end
    elsif a.is_a?(Array) && opt_b.nil? && opt_c.nil?
      # Method 2: diffs
      # Compute text1 from diffs.
      diffs = a
      text1 = diff_text1(diffs)
    elsif a.is_a?(String) && opt_b.is_a?(Array) && opt_c.nil?
      # Method 3: text1, diffs
      text1 = a
      diffs = opt_b
    elsif a.is_a?(String) && opt_b.is_a?(String) && opt_c.is_a?(Array)
      # Method 4: text1, text2, diffs
      # text2 is not used.
      text1 = a
      diffs = opt_c
    else
      raise Error, 'Unknown call format to patch_make.'
    end

    return [] if diffs.empty? # Get rid of the null case.

    patches = []
    patch = Patch.new
    patch_diff_length = 0 # Keeping our own length var is faster in JS.
    char_count1 = 0 # Number of characters into the text1 string.
    char_count2 = 0 # Number of characters into the text2 string.
    # Start with text1 (prepatch_text) and apply the diffs until we arrive at
    # text2 (postpatch_text).  We recreate the patches one by one to determine
    # context info.
    prepatch_text = text1
    postpatch_text = text1
    diffs.each_with_index do |diff, x|
      diff_type = diff[0]
      diff_text = diff[1]

      if patch_diff_length.zero? && diff_type != DIFF_EQUAL
        # A new patch starts here.
        patch.start1 = char_count1
        patch.start2 = char_count2
      end

      case diff_type
      when DIFF_INSERT
        patch.diffs[patch_diff_length] = diff
        patch_diff_length += 1
        patch.length2 += diff_text.length
        postpatch_text = JsString.substring(postpatch_text, 0, char_count2) + diff_text +
                         JsString.substring(postpatch_text, char_count2)
      when DIFF_DELETE
        patch.length1 += diff_text.length
        patch.diffs[patch_diff_length] = diff
        patch_diff_length += 1
        postpatch_text = JsString.substring(postpatch_text, 0, char_count2) +
                         JsString.substring(postpatch_text, char_count2 + diff_text.length)
      when DIFF_EQUAL
        if diff_text.length <= 2 * resolved.patch_margin &&
           patch_diff_length.positive? && diffs.length != x + 1
          # Small equality inside a patch.
          patch.diffs[patch_diff_length] = diff
          patch_diff_length += 1
          patch.length1 += diff_text.length
          patch.length2 += diff_text.length
        elsif diff_text.length >= 2 * resolved.patch_margin
          # Time for a new patch.
          if patch_diff_length.positive?
            patch_add_context(patch, prepatch_text, resolved)
            patches.push(patch)
            patch = Patch.new
            patch_diff_length = 0
            # Unlike Unidiff, our patch lists have a rolling context.
            # https://github.com/google/diff-match-patch/wiki/Unidiff
            # Update prepatch text & pos to reflect the application of the
            # just completed patch.
            prepatch_text = postpatch_text
            char_count1 = char_count2
          end
        end
      end

      # Update the current character count.
      char_count1 += diff_text.length if diff_type != DIFF_INSERT
      char_count2 += diff_text.length if diff_type != DIFF_DELETE
    end
    # Pick up the leftover patch if not empty.
    if patch_diff_length.positive?
      patch_add_context(patch, prepatch_text, resolved)
      patches.push(patch)
    end

    patches
  end

  # Given an array of patches, return another array that is identical.
  def patch_deep_copy(patches)
    patches.map do |patch|
      patch_copy = Patch.new
      patch_copy.diffs = patch.diffs.map { |(op, text)| create_diff(op, text) }
      patch_copy.start1 = patch.start1
      patch_copy.start2 = patch.start2
      patch_copy.length1 = patch.length1
      patch_copy.length2 = patch.length2
      patch_copy
    end
  end

  # Merge a set of patches onto the text.  Return a patched text, as well
  # as a list of true/false values indicating which patches were applied.
  def patch_apply(patches, text, options = nil)
    return [text, []] if patches.empty?

    # Deep copy the patches so that no changes are made to originals.
    patches = patch_deep_copy(patches)

    resolved = resolve_options(options)
    null_padding = patch_add_padding(patches, resolved)
    text = null_padding + text + null_padding

    patch_split_max(patches, resolved)
    # delta keeps track of the offset between the expected and actual
    # location of the previous patch.  If there are patches expected at
    # positions 10 and 20, but the first patch was found at 12, delta is 2
    # and the second patch has an effective expected position of 22.
    delta = 0
    results = []
    patches.each_with_index do |patch, x|
      expected_loc = patch.start2 + delta
      text1 = diff_text1(patch.diffs)
      end_loc = -1
      if text1.length > resolved.match_max_bits
        # patch_split_max will only provide an oversized pattern in the case
        # of a monster delete.
        start_loc = match_main(
          text,
          JsString.substring(text1, 0, resolved.match_max_bits),
          expected_loc,
          resolved,
        )
        if start_loc != -1
          end_loc = match_main(
            text,
            JsString.substring(text1, text1.length - resolved.match_max_bits),
            expected_loc + text1.length - resolved.match_max_bits,
            resolved,
          )
          if end_loc == -1 || start_loc >= end_loc
            # Can't find valid trailing context.  Drop this patch.
            start_loc = -1
          end
        end
      else
        start_loc = match_main(text, text1, expected_loc, resolved)
      end
      if start_loc == -1
        # No match found.  :(
        results[x] = false
        # Subtract the delta for this failed patch from subsequent patches.
        delta -= patch.length2 - patch.length1
      else
        # Found a match.  :)
        results[x] = true
        delta = start_loc - expected_loc
        text2 = if end_loc == -1
                  JsString.substring(text, start_loc, start_loc + text1.length)
                else
                  JsString.substring(text, start_loc, end_loc + resolved.match_max_bits)
                end

        if text1 == text2
          # Perfect match, just shove the replacement text in.
          text = JsString.substring(text, 0, start_loc) +
                 diff_text2(patch.diffs) +
                 JsString.substring(text, start_loc + text1.length)
        else
          # Imperfect match.  Run a diff to get a framework of equivalent
          # indices.
          diffs = diff_main(text1, text2, resolved, false)
          if text1.length > resolved.match_max_bits &&
             diff_levenshtein(diffs).fdiv(text1.length) > resolved.patch_delete_threshold
            # The end points match, but the content is unacceptably bad.
            results[x] = false
          else
            diff_cleanup_semantic_lossless(diffs)
            index1 = 0
            index2 = 0
            patch.diffs.each do |mod|
              index2 = diff_x_index(diffs, index1) if mod[0] != DIFF_EQUAL
              if mod[0] == DIFF_INSERT # Insertion
                text = JsString.substring(text, 0, start_loc + index2) + mod[1] +
                       JsString.substring(text, start_loc + index2)
              elsif mod[0] == DIFF_DELETE # Deletion
                text = JsString.substring(text, 0, start_loc + index2) +
                       JsString.substring(text, start_loc + diff_x_index(diffs, index1 + mod[1].length))
              end
              index1 += mod[1].length if mod[0] != DIFF_DELETE
            end
          end
        end
      end
    end
    # Strip the padding off.
    text = JsString.substring(text, null_padding.length, text.length - null_padding.length)
    [text, results]
  end

  # Add some padding on text start and end so that edges can match something.
  # Intended to be called only from within patch_apply.
  # Returns the padding string added to each side.
  def patch_add_padding(patches, options = nil)
    padding_length = resolve_options(options).patch_margin
    null_padding = +''
    (1..padding_length).each { |x| null_padding << x.chr(Encoding::UTF_8) }

    # Bump all the patches forward.
    patches.each do |patch|
      patch.start1 += padding_length
      patch.start2 += padding_length
    end

    # Add some padding on start of first diff.
    patch = patches[0]
    diffs = patch.diffs
    if diffs.empty? || diffs[0][0] != DIFF_EQUAL
      # Add null_padding equality.
      diffs.unshift(create_diff(DIFF_EQUAL, null_padding))
      patch.start1 -= padding_length # Should be 0.
      patch.start2 -= padding_length # Should be 0.
      patch.length1 += padding_length
      patch.length2 += padding_length
    elsif padding_length > diffs[0][1].length
      # Grow first equality.
      extra_length = padding_length - diffs[0][1].length
      diffs[0][1] = JsString.substring(null_padding, diffs[0][1].length) + diffs[0][1]
      patch.start1 -= extra_length
      patch.start2 -= extra_length
      patch.length1 += extra_length
      patch.length2 += extra_length
    end

    # Add some padding on end of last diff.
    patch = patches[patches.length - 1]
    diffs = patch.diffs
    if diffs.empty? || diffs[diffs.length - 1][0] != DIFF_EQUAL
      # Add null_padding equality.
      diffs.push(create_diff(DIFF_EQUAL, null_padding))
      patch.length1 += padding_length
      patch.length2 += padding_length
    elsif padding_length > diffs[diffs.length - 1][1].length
      # Grow last equality.
      extra_length = padding_length - diffs[diffs.length - 1][1].length
      diffs[diffs.length - 1][1] += JsString.substring(null_padding, 0, extra_length)
      patch.length1 += extra_length
      patch.length2 += extra_length
    end

    null_padding
  end

  # Look through the patches and break up any which are longer than the
  # maximum limit of the match algorithm.
  # Intended to be called only from within patch_apply.
  def patch_split_max(patches, options = nil)
    resolved = resolve_options(options)
    x = 0
    while x < patches.length
      if patches[x].length1 <= resolved.match_max_bits
        x += 1
        next
      end

      bigpatch = patches[x]
      # Remove the big old patch.
      patches.delete_at(x)
      x -= 1
      start1 = bigpatch.start1
      start2 = bigpatch.start2
      precontext = ''
      until bigpatch.diffs.empty?
        # Create one of several smaller patches.
        patch = Patch.new
        empty = true
        patch.start1 = start1 - precontext.length
        patch.start2 = start2 - precontext.length
        unless precontext.empty?
          patch.length1 = patch.length2 = precontext.length
          patch.diffs.push(create_diff(DIFF_EQUAL, precontext))
        end
        while !bigpatch.diffs.empty? &&
              patch.length1 < resolved.match_max_bits - resolved.patch_margin
          diff_type = bigpatch.diffs[0][0]
          diff_text = bigpatch.diffs[0][1]
          if diff_type == DIFF_INSERT
            # Insertions are harmless.
            patch.length2 += diff_text.length
            start2 += diff_text.length
            patch.diffs.push(bigpatch.diffs.shift)
            empty = false
          elsif diff_type == DIFF_DELETE && patch.diffs.length == 1 &&
                patch.diffs[0][0] == DIFF_EQUAL &&
                diff_text.length > 2 * resolved.match_max_bits
            # This is a large deletion.  Let it pass in one chunk.
            patch.length1 += diff_text.length
            start1 += diff_text.length
            empty = false
            patch.diffs.push(create_diff(diff_type, diff_text))
            bigpatch.diffs.shift
          else
            # Deletion or equality.  Only take as much as we can stomach.
            diff_text = JsString.substring(
              diff_text, 0, resolved.match_max_bits - patch.length1 - resolved.patch_margin
            )
            patch.length1 += diff_text.length
            start1 += diff_text.length
            if diff_type == DIFF_EQUAL
              patch.length2 += diff_text.length
              start2 += diff_text.length
            else
              empty = false
            end
            patch.diffs.push(create_diff(diff_type, diff_text))
            if diff_text == bigpatch.diffs[0][1]
              bigpatch.diffs.shift
            else
              bigpatch.diffs[0][1] = JsString.substring(bigpatch.diffs[0][1], diff_text.length)
            end
          end
        end
        # Compute the head context for the next patch.
        precontext = diff_text2(patch.diffs)
        precontext = JsString.substring(precontext, precontext.length - resolved.patch_margin)
        # Append the end context for this patch.
        postcontext = JsString.substring(diff_text1(bigpatch.diffs), 0, resolved.patch_margin)
        unless postcontext.empty?
          patch.length1 += postcontext.length
          patch.length2 += postcontext.length
          if !patch.diffs.empty? && patch.diffs[patch.diffs.length - 1][0] == DIFF_EQUAL
            patch.diffs[patch.diffs.length - 1][1] += postcontext
          else
            patch.diffs.push(create_diff(DIFF_EQUAL, postcontext))
          end
        end
        unless empty
          x += 1
          patches.insert(x, patch)
        end
      end
      x += 1
    end
    nil
  end

  # Take a list of patches and return a textual representation.
  def patch_to_text(patches)
    patches.map(&:to_s).join
  end

  # Parse a textual representation of patches and return a list of Patch
  # objects.
  def patch_from_text(textline)
    patches = []
    return patches if textline.nil? || textline.empty?

    text = textline.split("\n", -1)
    text_pointer = 0
    patch_header = /\A@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@\z/
    while text_pointer < text.length
      m = patch_header.match(text[text_pointer])
      raise Error, "Invalid patch string: #{text[text_pointer]}" unless m

      patch = Patch.new
      patches.push(patch)
      patch.start1 = m[1].to_i
      if m[2] == ''
        patch.start1 -= 1
        patch.length1 = 1
      elsif m[2] == '0'
        patch.length1 = 0
      else
        patch.start1 -= 1
        patch.length1 = m[2].to_i
      end

      patch.start2 = m[3].to_i
      if m[4] == ''
        patch.start2 -= 1
        patch.length2 = 1
      elsif m[4] == '0'
        patch.length2 = 0
      else
        patch.start2 -= 1
        patch.length2 = m[4].to_i
      end
      text_pointer += 1

      while text_pointer < text.length
        sign = JsString.char_at(text[text_pointer], 0)
        line = ''
        begin
          line = JsString.decode_uri(JsString.substring(text[text_pointer], 1))
        rescue JsString::UriError
          # Malformed URI sequence.  (The reference implementation reports the
          # pre-assignment value of `line`, which is always empty.)
          raise Error, 'Illegal escape in patch_fromText: '
        end
        case sign
        when '-'
          # Deletion.
          patch.diffs.push(create_diff(DIFF_DELETE, line))
        when '+'
          # Insertion.
          patch.diffs.push(create_diff(DIFF_INSERT, line))
        when ' '
          # Minor equality.
          patch.diffs.push(create_diff(DIFF_EQUAL, line))
        when '@'
          # Start of next patch.
          break
        when ''
          # Blank line?  Whatever.
        else
          # WTF?
          raise Error, "Invalid patch mode \"#{sign}\" in: #{line}"
        end
        text_pointer += 1
      end
    end
    patches
  end
end
