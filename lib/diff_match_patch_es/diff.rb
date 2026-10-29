# frozen_string_literal: true

module DiffMatchPatchES
  DIFF_DELETE = -1
  DIFF_INSERT = 1
  DIFF_EQUAL = 0

  # Line-mode diffing maps each unique line to a single character. JavaScript
  # strings tolerate lone surrogates (code units 0xD800..0xDFFF) but UTF-8
  # cannot represent them, so indices at or above 0xD800 shift up by 0x800.
  # The mapping is injective either way, and the diff algorithm only observes
  # equality between these placeholder characters, so results are identical.
  LINE_INDEX_SURROGATE_SHIFT = 0x800
  private_constant :LINE_INDEX_SURROGATE_SHIFT

  module_function

  def create_diff(op, text)
    [op, text]
  end

  def now_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
  end
  private_class_method :now_ms

  # Find the differences between two texts.
  def diff_main(text1, text2, options = nil, checklines = true, deadline = nil)
    resolved = resolve_options(options)

    if deadline.nil?
      deadline = if resolved.diff_timeout <= 0
                   Float::MAX
                 else
                   now_ms + resolved.diff_timeout * 1000
                 end
    end

    raise Error, 'Null input. (diff_main)' if text1.nil? || text2.nil?

    if text1 == text2
      return [create_diff(DIFF_EQUAL, text1)] unless text1.empty?

      return []
    end

    # Trim off common prefix (speedup).
    commonlength = diff_common_prefix(text1, text2)
    commonprefix = JsString.substring(text1, 0, commonlength)
    text1 = JsString.substring(text1, commonlength)
    text2 = JsString.substring(text2, commonlength)

    # Trim off common suffix (speedup).
    commonlength = diff_common_suffix(text1, text2)
    commonsuffix = JsString.substring(text1, text1.length - commonlength)
    text1 = JsString.substring(text1, 0, text1.length - commonlength)
    text2 = JsString.substring(text2, 0, text2.length - commonlength)

    # Compute the diff on the middle block.
    diffs = diff_compute(text1, text2, resolved, checklines, deadline)

    # Restore the prefix and suffix.
    diffs.unshift(create_diff(DIFF_EQUAL, commonprefix)) unless commonprefix.empty?
    diffs.push(create_diff(DIFF_EQUAL, commonsuffix)) unless commonsuffix.empty?

    diff_cleanup_merge!(diffs)
    diffs
  end

  # Find the differences between two texts. Assumes that the texts do not
  # have any common prefix or suffix.
  def diff_compute(text1, text2, options, checklines, deadline)
    # Just add some text (speedup).
    return [create_diff(DIFF_INSERT, text2)] if text1.empty?

    # Just delete some text (speedup).
    return [create_diff(DIFF_DELETE, text1)] if text2.empty?

    longtext = text1.length > text2.length ? text1 : text2
    shorttext = text1.length > text2.length ? text2 : text1
    i = longtext.index(shorttext)
    unless i.nil?
      # Shorter text is inside the longer text (speedup).
      diffs = [
        create_diff(DIFF_INSERT, JsString.substring(longtext, 0, i)),
        create_diff(DIFF_EQUAL, shorttext),
        create_diff(DIFF_INSERT, JsString.substring(longtext, i + shorttext.length)),
      ]
      # Swap insertions for deletions if diff is reversed.
      diffs[0][0] = diffs[2][0] = DIFF_DELETE if text1.length > text2.length

      return diffs
    end

    if shorttext.length == 1
      # Single character string.
      # After the previous speedup, the character can't be an equality.
      return [create_diff(DIFF_DELETE, text1), create_diff(DIFF_INSERT, text2)]
    end

    # Check to see if the problem can be split in two.
    hm = diff_half_match(text1, text2, options)
    if hm
      # A half-match was found, sort out the return data.
      text1_a, text1_b, text2_a, text2_b, mid_common = hm
      # Send both pairs off for separate processing.
      diffs_a = diff_main(text1_a, text2_a, options, checklines, deadline)
      diffs_b = diff_main(text1_b, text2_b, options, checklines, deadline)
      # Merge the results.
      return diffs_a.concat([create_diff(DIFF_EQUAL, mid_common)], diffs_b)
    end

    return diff_line_mode(text1, text2, options, deadline) if checklines && text1.length > 100 && text2.length > 100

    diff_bisect(text1, text2, options, deadline)
  end

  # Do a quick line-level diff on both strings, then re-diff the parts for
  # greater accuracy. This speedup can produce non-minimal diffs.
  def diff_line_mode(text1, text2, options, deadline)
    # Scan the text on a line-by-line basis first.
    a = diff_lines_to_chars(text1, text2)
    text1 = a[:chars1]
    text2 = a[:chars2]
    linearray = a[:line_array]

    diffs = diff_main(text1, text2, options, false, deadline)

    # Convert the diff back to original text.
    diff_chars_to_lines!(diffs, linearray)
    # Eliminate freak matches (e.g. blank lines)
    diff_cleanup_semantic!(diffs)

    # Re-diff any replacement blocks, this time character-by-character.
    # Add a dummy entry at the end.
    diffs.push(create_diff(DIFF_EQUAL, ''))
    pointer = 0
    count_delete = 0
    count_insert = 0
    text_delete = +''
    text_insert = +''
    while pointer < diffs.length
      case diffs[pointer][0]
      when DIFF_INSERT
        count_insert += 1
        text_insert += diffs[pointer][1]
      when DIFF_DELETE
        count_delete += 1
        text_delete += diffs[pointer][1]
      when DIFF_EQUAL
        # Upon reaching an equality, check for prior redundancies.
        if count_delete >= 1 && count_insert >= 1
          # Delete the offending records and add the merged ones.
          diffs.slice!(pointer - count_delete - count_insert, count_delete + count_insert)
          pointer = pointer - count_delete - count_insert
          sub_diff = diff_main(text_delete, text_insert, options, false, deadline)
          (sub_diff.length - 1).downto(0) do |j|
            diffs.insert(pointer, sub_diff[j])
          end
          pointer += sub_diff.length
        end
        count_insert = 0
        count_delete = 0
        text_delete = +''
        text_insert = +''
      end
      pointer += 1
    end
    diffs.pop # Remove the dummy entry at the end.

    diffs
  end

  # Find the 'middle snake' of a diff, split the problem in two
  # and return the recursively constructed diff.
  # See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
  def diff_bisect(text1, text2, options, deadline)
    # Cache the text lengths to prevent multiple calls.
    text1_length = text1.length
    text2_length = text2.length
    # Avoid allocations by comparing codepoints below instead of strings
    units1, units2 = diff_bisect_units(text1, text2)
    max_d = (text1_length + text2_length + 1) / 2
    v_offset = max_d
    v_length = 2 * max_d
    v1 = Array.new(v_length, -1)
    v2 = Array.new(v_length, -1)
    v1[v_offset + 1] = 0
    v2[v_offset + 1] = 0
    delta = text1_length - text2_length
    # If the total number of characters is odd, then the front path will collide
    # with the reverse path.
    front = delta.odd?
    # Offsets for start and end of k loop.
    # Prevents mapping of space beyond the grid.
    k1start = 0
    k1end = 0
    k2start = 0
    k2end = 0
    d = 0
    while d < max_d
      # Bail out if deadline is reached.
      break if now_ms > deadline

      # Walk the front path one step.
      k1 = -d + k1start
      while k1 <= d - k1end
        k1_offset = v_offset + k1
        x1 = if k1 == -d || (k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1])
               v1[k1_offset + 1]
             else
               v1[k1_offset - 1] + 1
             end
        y1 = x1 - k1
        while x1 < text1_length && y1 < text2_length && units1[x1] == units2[y1]
          x1 += 1
          y1 += 1
        end
        v1[k1_offset] = x1
        if x1 > text1_length
          # Ran off the right of the graph.
          k1end += 2
        elsif y1 > text2_length
          # Ran off the bottom of the graph.
          k1start += 2
        elsif front
          k2_offset = v_offset + delta - k1
          if k2_offset >= 0 && k2_offset < v_length && v2[k2_offset] != -1
            # Mirror x2 onto top-left coordinate system.
            x2 = text1_length - v2[k2_offset]
            if x1 >= x2
              # Overlap detected.
              return diff_bisect_split(text1, text2, options, x1, y1, deadline)
            end
          end
        end
        k1 += 2
      end

      # Walk the reverse path one step.
      k2 = -d + k2start
      while k2 <= d - k2end
        k2_offset = v_offset + k2
        x2 = if k2 == -d || (k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1])
               v2[k2_offset + 1]
             else
               v2[k2_offset - 1] + 1
             end
        y2 = x2 - k2
        while x2 < text1_length && y2 < text2_length &&
              units1[text1_length - x2 - 1] == units2[text2_length - y2 - 1]
          x2 += 1
          y2 += 1
        end
        v2[k2_offset] = x2
        if x2 > text1_length
          # Ran off the left of the graph.
          k2end += 2
        elsif y2 > text2_length
          # Ran off the top of the graph.
          k2start += 2
        elsif !front
          k1_offset = v_offset + delta - k2
          if k1_offset >= 0 && k1_offset < v_length && v1[k1_offset] != -1
            x1 = v1[k1_offset]
            y1 = v_offset + x1 - k1_offset
            # Mirror x2 onto top-left coordinate system.
            x2 = text1_length - x2
            if x1 >= x2
              # Overlap detected.
              return diff_bisect_split(text1, text2, options, x1, y1, deadline)
            end
          end
        end
        k2 += 2
      end
      d += 1
    end
    # Diff took too long and hit the deadline or
    # number of diffs equals number of characters, no commonality at all.
    [create_diff(DIFF_DELETE, text1), create_diff(DIFF_INSERT, text2)]
  end

  # Given the location of the 'middle snake', split the diff in two parts
  # and recurse.
  def diff_bisect_split(text1, text2, options, x, y, deadline)
    text1a = JsString.substring(text1, 0, x)
    text2a = JsString.substring(text2, 0, y)
    text1b = JsString.substring(text1, x)
    text2b = JsString.substring(text2, y)

    # Compute both diffs serially.
    diffs = diff_main(text1a, text2a, options, false, deadline)
    diffsb = diff_main(text1b, text2b, options, false, deadline)

    diffs.concat(diffsb)
  end

  def diff_bisect_units(text1, text2)
    if text1.valid_encoding? && text2.valid_encoding?
      [text1.codepoints, text2.codepoints]
    else
      [text1.chars, text2.chars]
    end
  end
  private_class_method :diff_bisect_units

  def line_char_for(index)
    codepoint = index < 0xD800 ? index : index + LINE_INDEX_SURROGATE_SHIFT
    codepoint.chr(Encoding::UTF_8)
  end
  private_class_method :line_char_for

  def line_index_for(char)
    codepoint = char.ord
    codepoint < 0xD800 ? codepoint : codepoint - LINE_INDEX_SURROGATE_SHIFT
  end
  private_class_method :line_index_for

  # Split two texts into an array of strings. Reduce the texts to a string of
  # placeholder characters where each character represents one line.
  def diff_lines_to_chars(text1, text2)
    line_array = [] # e.g. line_array[4] == "Hello\n"
    line_hash = {}  # e.g. line_hash["Hello\n"] == 4

    # Allocate 2/3rds of the space for text1, the rest for text2.
    max_lines = 40_000

    # '\x00' is a valid character, but various debuggers don't like it.
    # So we'll insert a junk entry to avoid generating a null character.
    line_array[0] = ''

    munge = lambda do |text|
      chars = +''
      # Walk the text, pulling out a substring for each line.
      line_start = 0
      line_end = -1
      line_array_length = line_array.length
      while line_end < text.length - 1
        line_end = text.index("\n", line_start) || -1
        line_end = text.length - 1 if line_end == -1

        line = JsString.substring(text, line_start, line_end + 1)

        if line_hash.key?(line)
          chars << line_char_for(line_hash[line])
        else
          if line_array_length == max_lines
            # Bail out at 65535 because
            # String.fromCharCode(65536) == String.fromCharCode(0)
            line = JsString.substring(text, line_start)
            line_end = text.length
          end
          chars << line_char_for(line_array_length)
          line_hash[line] = line_array_length
          line_array[line_array_length] = line
          line_array_length += 1
        end
        line_start = line_end + 1
      end
      chars
    end

    chars1 = munge.call(text1)
    max_lines = 65_535
    chars2 = munge.call(text2)
    { chars1: chars1, chars2: chars2, line_array: line_array }
  end

  # Rehydrate the text in a diff from a string of line placeholders to real
  # lines of text.
  def diff_chars_to_lines!(diffs, line_array)
    diffs.each do |diff|
      chars = diff[1]
      text = +''
      chars.each_char { |ch| text << line_array[line_index_for(ch)] }
      diff[1] = text
    end
    nil
  end

  # Determine the common prefix of two strings.
  def diff_common_prefix(text1, text2)
    # Quick check for common null cases.
    return 0 if text1.empty? || text2.empty? || text1[0] != text2[0]

    # Binary search.
    # Performance analysis: https://neil.fraser.name/news/2007/10/09/
    pointermin = 0
    pointermax = [text1.length, text2.length].min
    pointermid = pointermax
    pointerstart = 0
    while pointermin < pointermid
      if JsString.substring(text1, pointerstart, pointermid) ==
         JsString.substring(text2, pointerstart, pointermid)
        pointermin = pointermid
        pointerstart = pointermin
      else
        pointermax = pointermid
      end
      pointermid = (pointermax - pointermin) / 2 + pointermin
    end
    pointermid
  end

  # Determine the common suffix of two strings.
  def diff_common_suffix(text1, text2)
    # Quick check for common null cases.
    return 0 if text1.empty? || text2.empty? || text1[-1] != text2[-1]

    # Binary search.
    # Performance analysis: https://neil.fraser.name/news/2007/10/09/
    pointermin = 0
    pointermax = [text1.length, text2.length].min
    pointermid = pointermax
    pointerend = 0
    while pointermin < pointermid
      if JsString.substring(text1, text1.length - pointermid, text1.length - pointerend) ==
         JsString.substring(text2, text2.length - pointermid, text2.length - pointerend)
        pointermin = pointermid
        pointerend = pointermin
      else
        pointermax = pointermid
      end
      pointermid = (pointermax - pointermin) / 2 + pointermin
    end
    pointermid
  end

  # Determine if the suffix of one string is the prefix of another.
  def diff_common_overlap(text1, text2)
    # Cache the text lengths to prevent multiple calls.
    text1_length = text1.length
    text2_length = text2.length
    # Eliminate the null case.
    return 0 if text1_length.zero? || text2_length.zero?

    # Truncate the longer string.
    if text1_length > text2_length
      text1 = JsString.substring(text1, text1_length - text2_length)
    elsif text1_length < text2_length
      text2 = JsString.substring(text2, 0, text1_length)
    end

    text_length = [text1_length, text2_length].min
    # Quick check for the worst case.
    return text_length if text1 == text2

    # Start by looking for a single character match
    # and increase length until no match is found.
    # Performance analysis: https://neil.fraser.name/news/2010/11/04/
    best = 0
    length = 1
    loop do
      pattern = JsString.substring(text1, text_length - length)
      found = JsString.index_of(text2, pattern)
      return best if found == -1

      length += found
      if found.zero? || JsString.substring(text1, text_length - length) == JsString.substring(text2, 0, length)
        best = length
        length += 1
      end
    end
  end

  # Do the two texts share a substring which is at least half the length of
  # the longer text? This speedup can produce non-minimal diffs.
  def diff_half_match(text1, text2, options)
    if options.diff_timeout <= 0
      # Don't risk returning a non-optimal diff if we have unlimited time.
      return nil
    end
    longtext = text1.length > text2.length ? text1 : text2
    shorttext = text1.length > text2.length ? text2 : text1
    return nil if longtext.length < 4 || shorttext.length * 2 < longtext.length # Pointless.

    # First check if the second quarter is the seed for a half-match.
    hm1 = diff_half_match_i(longtext, shorttext, (longtext.length + 3) / 4)
    # Check again based on the third quarter.
    hm2 = diff_half_match_i(longtext, shorttext, (longtext.length + 1) / 2)

    if !hm1 && !hm2
      return nil
    elsif !hm2
      hm = hm1
    elsif !hm1
      hm = hm2
    else
      # Both matched.  Select the longest.
      hm = hm1[4].length > hm2[4].length ? hm1 : hm2
    end

    # A half-match was found, sort out the return data.
    if text1.length > text2.length
      text1_a, text1_b, text2_a, text2_b = hm
    else
      text2_a, text2_b, text1_a, text1_b = hm
    end
    mid_common = hm[4]
    [text1_a, text1_b, text2_a, text2_b, mid_common]
  end

  # Does a substring of shorttext exist within longtext such that the
  # substring is at least half the length of longtext?
  def diff_half_match_i(longtext, shorttext, i)
    # Start with a 1/4 length substring at position i as a seed.
    seed = JsString.substring(longtext, i, i + (longtext.length / 4))
    j = -1
    best_common = ''
    best_longtext_a = best_longtext_b = best_shorttext_a = best_shorttext_b = nil
    while (j = JsString.index_of(shorttext, seed, j + 1)) != -1
      prefix_length = diff_common_prefix(JsString.substring(longtext, i), JsString.substring(shorttext, j))
      suffix_length = diff_common_suffix(JsString.substring(longtext, 0, i), JsString.substring(shorttext, 0, j))
      next unless best_common.length < suffix_length + prefix_length

      best_common = JsString.substring(shorttext, j - suffix_length, j) +
                    JsString.substring(shorttext, j, j + prefix_length)
      best_longtext_a = JsString.substring(longtext, 0, i - suffix_length)
      best_longtext_b = JsString.substring(longtext, i + prefix_length)
      best_shorttext_a = JsString.substring(shorttext, 0, j - suffix_length)
      best_shorttext_b = JsString.substring(shorttext, j + prefix_length)
    end
    if best_common.length * 2 >= longtext.length
      [best_longtext_a, best_longtext_b, best_shorttext_a, best_shorttext_b, best_common]
    end
  end

  # Reduce the number of edits by eliminating semantically trivial equalities.
  def diff_cleanup_semantic!(diffs)
    changes = false
    # Stack of indices where equalities are found. The reference
    # implementation lets the stack pointer go negative and stores into the
    # JS array at index -1 (a plain property write), so a Hash reproduces
    # those semantics.
    equalities = {}
    equalities_length = 0
    last_equality = nil
    # Always equal to diffs[equalities[equalities_length - 1]][1]
    pointer = 0 # Index of current position.

    # Number of characters that changed prior to the equality.
    length_insertions1 = 0
    length_deletions1 = 0
    # Number of characters that changed after the equality.
    length_insertions2 = 0
    length_deletions2 = 0
    while pointer < diffs.length
      if diffs[pointer][0] == DIFF_EQUAL # Equality found.
        equalities[equalities_length] = pointer
        equalities_length += 1
        length_insertions1 = length_insertions2
        length_deletions1 = length_deletions2
        length_insertions2 = 0
        length_deletions2 = 0
        last_equality = diffs[pointer][1]
      else # An insertion or deletion.
        if diffs[pointer][0] == DIFF_INSERT
          length_insertions2 += diffs[pointer][1].length
        else
          length_deletions2 += diffs[pointer][1].length
        end

        # Eliminate an equality that is smaller or equal to the edits on both
        # sides of it.
        if last_equality &&
           last_equality.length <= [length_insertions1, length_deletions1].max &&
           last_equality.length <= [length_insertions2, length_deletions2].max
          # Duplicate record.
          diffs.insert(equalities[equalities_length - 1], create_diff(DIFF_DELETE, last_equality))
          # Change second copy to insert.
          diffs[equalities[equalities_length - 1] + 1][0] = DIFF_INSERT
          # Throw away the equality we just deleted.
          equalities_length -= 1
          # Throw away the previous equality (it needs to be reevaluated).
          equalities_length -= 1
          pointer = equalities_length.positive? ? equalities[equalities_length - 1] : -1
          length_insertions1 = 0 # Reset the counters.
          length_deletions1 = 0
          length_insertions2 = 0
          length_deletions2 = 0
          last_equality = nil
          changes = true
        end
      end
      pointer += 1
    end

    # Normalize the diff.
    diff_cleanup_merge!(diffs) if changes

    diff_cleanup_semantic_lossless!(diffs)

    # Find any overlaps between deletions and insertions.
    # e.g: <del>abcxxx</del><ins>xxxdef</ins>
    #   -> <del>abc</del>xxx<ins>def</ins>
    # e.g: <del>xxxabc</del><ins>defxxx</ins>
    #   -> <ins>def</ins>xxx<del>abc</del>
    # Only extract an overlap if it is as big as the edit ahead or behind it.
    pointer = 1
    while pointer < diffs.length
      if diffs[pointer - 1][0] == DIFF_DELETE && diffs[pointer][0] == DIFF_INSERT
        deletion = diffs[pointer - 1][1]
        insertion = diffs[pointer][1]
        overlap_length1 = diff_common_overlap(deletion, insertion)
        overlap_length2 = diff_common_overlap(insertion, deletion)
        if overlap_length1 >= overlap_length2
          if overlap_length1 >= deletion.length / 2.0 || overlap_length1 >= insertion.length / 2.0
            # Overlap found.  Insert an equality and trim the surrounding edits.
            diffs.insert(pointer, create_diff(DIFF_EQUAL, JsString.substring(insertion, 0, overlap_length1)))
            diffs[pointer - 1][1] = JsString.substring(deletion, 0, deletion.length - overlap_length1)
            diffs[pointer + 1][1] = JsString.substring(insertion, overlap_length1)
            pointer += 1
          end
        elsif overlap_length2 >= deletion.length / 2.0 || overlap_length2 >= insertion.length / 2.0
          # Reverse overlap found.
          # Insert an equality and swap and trim the surrounding edits.
          diffs.insert(pointer, create_diff(DIFF_EQUAL, JsString.substring(deletion, 0, overlap_length2)))
          diffs[pointer - 1][0] = DIFF_INSERT
          diffs[pointer - 1][1] = JsString.substring(insertion, 0, insertion.length - overlap_length2)
          diffs[pointer + 1][0] = DIFF_DELETE
          diffs[pointer + 1][1] = JsString.substring(deletion, overlap_length2)
          pointer += 1
        end
        pointer += 1
      end
      pointer += 1
    end
    nil
  end

  NON_ALPHA_NUMERIC_REGEX = /[^a-z0-9]/i
  # Matches the JS \s class (which the reference implementation uses).
  WHITESPACE_REGEX = /[\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]/
  LINEBREAK_REGEX = /[\r\n]/
  BLANKLINE_END_REGEX = /\n\r?\n\z/
  BLANKLINE_START_REGEX = /\A\r?\n\r?\n/

  # Given two strings, compute a score representing whether the internal
  # boundary falls on logical boundaries.
  # Scores range from 6 (best) to 0 (worst).
  def diff_cleanup_semantic_score(one, two)
    if one.empty? || two.empty?
      # Edges are the best.
      return 6
    end

    char1 = one[-1]
    char2 = two[0]
    non_alpha_numeric1 = NON_ALPHA_NUMERIC_REGEX.match?(char1)
    non_alpha_numeric2 = NON_ALPHA_NUMERIC_REGEX.match?(char2)
    whitespace1 = non_alpha_numeric1 && WHITESPACE_REGEX.match?(char1)
    whitespace2 = non_alpha_numeric2 && WHITESPACE_REGEX.match?(char2)
    line_break1 = whitespace1 && LINEBREAK_REGEX.match?(char1)
    line_break2 = whitespace2 && LINEBREAK_REGEX.match?(char2)
    blank_line1 = line_break1 && BLANKLINE_END_REGEX.match?(one)
    blank_line2 = line_break2 && BLANKLINE_START_REGEX.match?(two)

    if blank_line1 || blank_line2
      # Five points for blank lines.
      5
    elsif line_break1 || line_break2
      # Four points for line breaks.
      4
    elsif non_alpha_numeric1 && !whitespace1 && whitespace2
      # Three points for end of sentences.
      3
    elsif whitespace1 || whitespace2
      # Two points for whitespace.
      2
    elsif non_alpha_numeric1 || non_alpha_numeric2
      # One point for non-alphanumeric.
      1
    else
      0
    end
  end

  # Look for single edits surrounded on both sides by equalities
  # which can be shifted sideways to align the edit to a word boundary.
  # e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
  def diff_cleanup_semantic_lossless!(diffs)
    pointer = 1
    # Intentionally ignore the first and last element (don't need checking).
    while pointer < diffs.length - 1
      if diffs[pointer - 1][0] == DIFF_EQUAL && diffs[pointer + 1][0] == DIFF_EQUAL
        # This is a single edit surrounded by equalities.
        equality1 = diffs[pointer - 1][1]
        edit = diffs[pointer][1]
        equality2 = diffs[pointer + 1][1]

        # First, shift the edit as far left as possible.
        common_offset = diff_common_suffix(equality1, edit)
        if common_offset.positive?
          common_string = JsString.substring(edit, edit.length - common_offset)
          equality1 = JsString.substring(equality1, 0, equality1.length - common_offset)
          edit = common_string + JsString.substring(edit, 0, edit.length - common_offset)
          equality2 = common_string + equality2
        end

        # Second, step character by character right, looking for the best fit.
        best_equality1 = equality1
        best_edit = edit
        best_equality2 = equality2
        best_score = diff_cleanup_semantic_score(equality1, edit) +
                     diff_cleanup_semantic_score(edit, equality2)
        while !edit.empty? && !equality2.empty? && edit[0] == equality2[0]
          equality1 += edit[0]
          edit = JsString.substring(edit, 1) + equality2[0]
          equality2 = JsString.substring(equality2, 1)
          score = diff_cleanup_semantic_score(equality1, edit) +
                  diff_cleanup_semantic_score(edit, equality2)
          # The >= encourages trailing rather than leading whitespace on edits.
          next unless score >= best_score

          best_score = score
          best_equality1 = equality1
          best_edit = edit
          best_equality2 = equality2
        end

        if diffs[pointer - 1][1] != best_equality1
          # We have an improvement, save it back to the diff.
          if best_equality1.empty?
            diffs.delete_at(pointer - 1)
            pointer -= 1
          else
            diffs[pointer - 1][1] = best_equality1
          end
          diffs[pointer][1] = best_edit
          if best_equality2.empty?
            diffs.delete_at(pointer + 1)
            pointer -= 1
          else
            diffs[pointer + 1][1] = best_equality2
          end
        end
      end
      pointer += 1
    end
    nil
  end

  # Reduce the number of edits by eliminating operationally trivial equalities.
  def diff_cleanup_efficiency!(diffs, options = nil)
    diff_edit_cost = resolve_options(options).diff_edit_cost

    changes = false
    # Stack of indices where equalities are found (Hash for the same
    # negative-index reason as in diff_cleanup_semantic!).
    equalities = {}
    equalities_length = 0
    last_equality = nil
    # Always equal to diffs[equalities[equalities_length - 1]][1]
    pointer = 0 # Index of current position.

    # Is there an insertion operation before the last equality.
    pre_ins = false
    # Is there a deletion operation before the last equality.
    pre_del = false
    # Is there an insertion operation after the last equality.
    post_ins = false
    # Is there a deletion operation after the last equality.
    post_del = false
    while pointer < diffs.length
      if diffs[pointer][0] == DIFF_EQUAL # Equality found.
        if diffs[pointer][1].length < diff_edit_cost && (post_ins || post_del)
          # Candidate found.
          equalities[equalities_length] = pointer
          equalities_length += 1
          pre_ins = post_ins
          pre_del = post_del
          last_equality = diffs[pointer][1]
        else
          # Not a candidate, and can never become one.
          equalities_length = 0
          last_equality = nil
        end
        post_ins = post_del = false
      else # An insertion or deletion.
        if diffs[pointer][0] == DIFF_DELETE
          post_del = true
        else
          post_ins = true
        end

        # Five types to be split:
        # <ins>A</ins><del>B</del>XY<ins>C</ins><del>D</del>
        # <ins>A</ins>X<ins>C</ins><del>D</del>
        # <ins>A</ins><del>B</del>X<ins>C</ins>
        # <ins>A</del>X<ins>C</ins><del>D</del>
        # <ins>A</ins><del>B</del>X<del>C</del>
        if last_equality && ((pre_ins && pre_del && post_ins && post_del) ||
          ((last_equality.length < diff_edit_cost / 2.0) &&
            [pre_ins, pre_del, post_ins, post_del].count(true) == 3))
          # Duplicate record.
          diffs.insert(equalities[equalities_length - 1], create_diff(DIFF_DELETE, last_equality))
          # Change second copy to insert.
          diffs[equalities[equalities_length - 1] + 1][0] = DIFF_INSERT
          equalities_length -= 1 # Throw away the equality we just deleted;
          last_equality = nil
          if pre_ins && pre_del
            # No changes made which could affect previous entry, keep going.
            post_ins = post_del = true
            equalities_length = 0
          else
            equalities_length -= 1 # Throw away the previous equality.
            pointer = equalities_length.positive? ? equalities[equalities_length - 1] : -1
            post_ins = post_del = false
          end
          changes = true
        end
      end
      pointer += 1
    end

    diff_cleanup_merge!(diffs) if changes
    nil
  end

  # Reorder and merge like edit sections.  Merge equalities.
  # Any edit section can move as long as it doesn't cross an equality.
  def diff_cleanup_merge!(diffs)
    # Add a dummy entry at the end.
    diffs.push(create_diff(DIFF_EQUAL, ''))
    pointer = 0
    count_delete = 0
    count_insert = 0
    text_delete = +''
    text_insert = +''
    while pointer < diffs.length
      case diffs[pointer][0]
      when DIFF_INSERT
        count_insert += 1
        text_insert += diffs[pointer][1]
        pointer += 1
      when DIFF_DELETE
        count_delete += 1
        text_delete += diffs[pointer][1]
        pointer += 1
      when DIFF_EQUAL
        # Upon reaching an equality, check for prior redundancies.
        if count_delete + count_insert > 1
          if count_delete != 0 && count_insert != 0
            # Factor out any common prefixes.
            commonlength = diff_common_prefix(text_insert, text_delete)
            if commonlength != 0
              if (pointer - count_delete - count_insert).positive? &&
                 diffs[pointer - count_delete - count_insert - 1][0] == DIFF_EQUAL
                diffs[pointer - count_delete - count_insert - 1][1] += JsString.substring(text_insert, 0, commonlength)
              else
                diffs.insert(0, create_diff(DIFF_EQUAL, JsString.substring(text_insert, 0, commonlength)))
                pointer += 1
              end
              text_insert = JsString.substring(text_insert, commonlength)
              text_delete = JsString.substring(text_delete, commonlength)
            end
            # Factor out any common suffixes.
            commonlength = diff_common_suffix(text_insert, text_delete)
            if commonlength != 0
              diffs[pointer][1] = JsString.substring(text_insert, text_insert.length - commonlength) + diffs[pointer][1]
              text_insert = JsString.substring(text_insert, 0, text_insert.length - commonlength)
              text_delete = JsString.substring(text_delete, 0, text_delete.length - commonlength)
            end
          end
          # Delete the offending records and add the merged ones.
          pointer -= count_delete + count_insert
          diffs.slice!(pointer, count_delete + count_insert)
          unless text_delete.empty?
            diffs.insert(pointer, create_diff(DIFF_DELETE, text_delete))
            pointer += 1
          end
          unless text_insert.empty?
            diffs.insert(pointer, create_diff(DIFF_INSERT, text_insert))
            pointer += 1
          end
          pointer += 1
        elsif pointer != 0 && diffs[pointer - 1][0] == DIFF_EQUAL
          # Merge this equality with the previous one.
          diffs[pointer - 1][1] += diffs[pointer][1]
          diffs.delete_at(pointer)
        else
          pointer += 1
        end
        count_insert = 0
        count_delete = 0
        text_delete = +''
        text_insert = +''
      end
    end
    diffs.pop if diffs[diffs.length - 1][1] == '' # Remove the dummy entry at the end.

    # Second pass: look for single edits surrounded on both sides by equalities
    # which can be shifted sideways to eliminate an equality.
    # e.g: A<ins>BA</ins>C -> <ins>AB</ins>AC
    changes = false
    pointer = 1
    # Intentionally ignore the first and last element (don't need checking).
    while pointer < diffs.length - 1
      if diffs[pointer - 1][0] == DIFF_EQUAL && diffs[pointer + 1][0] == DIFF_EQUAL
        # This is a single edit surrounded by equalities.
        if JsString.substring(diffs[pointer][1], diffs[pointer][1].length - diffs[pointer - 1][1].length) ==
           diffs[pointer - 1][1]
          # Shift the edit over the previous equality.
          diffs[pointer][1] = diffs[pointer - 1][1] +
                              JsString.substring(diffs[pointer][1], 0,
                                                 diffs[pointer][1].length - diffs[pointer - 1][1].length)
          diffs[pointer + 1][1] = diffs[pointer - 1][1] + diffs[pointer + 1][1]
          diffs.delete_at(pointer - 1)
          changes = true
        elsif JsString.substring(diffs[pointer][1], 0, diffs[pointer + 1][1].length) == diffs[pointer + 1][1]
          # Shift the edit over the next equality.
          diffs[pointer - 1][1] += diffs[pointer + 1][1]
          diffs[pointer][1] = JsString.substring(diffs[pointer][1], diffs[pointer + 1][1].length) +
                              diffs[pointer + 1][1]
          diffs.delete_at(pointer + 1)
          changes = true
        end
      end
      pointer += 1
    end
    # If shifts were made, the diff needs reordering and another shift sweep.
    diff_cleanup_merge!(diffs) if changes
    nil
  end

  # loc is a location in text1, compute and return the equivalent location in
  # text2. e.g. 'The cat' vs 'The big cat', 1->1, 5->8
  def diff_x_index(diffs, loc)
    chars1 = 0
    chars2 = 0
    last_chars1 = 0
    last_chars2 = 0
    x = 0
    while x < diffs.length
      if diffs[x][0] != DIFF_INSERT # Equality or deletion.
        chars1 += diffs[x][1].length
      end
      if diffs[x][0] != DIFF_DELETE # Equality or insertion.
        chars2 += diffs[x][1].length
      end
      break if chars1 > loc # Overshot the location.

      last_chars1 = chars1
      last_chars2 = chars2
      x += 1
    end
    # Was the location deleted?
    return last_chars2 if diffs.length != x && diffs[x][0] == DIFF_DELETE

    # Add the remaining character length.
    last_chars2 + (loc - last_chars1)
  end

  # Convert a diff array into a pretty HTML report.
  def diff_pretty_html(diffs)
    html = +''
    diffs.each do |(op, data)|
      text = data.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub("\n", '&para;<br>')
      case op
      when DIFF_INSERT
        html << %(<ins style="background:#e6ffe6;">#{text}</ins>)
      when DIFF_DELETE
        html << %(<del style="background:#ffe6e6;">#{text}</del>)
      when DIFF_EQUAL
        html << "<span>#{text}</span>"
      end
    end
    html
  end

  # Compute and return the source text (all equalities and deletions).
  def diff_text1(diffs)
    text = +''
    diffs.each { |(op, data)| text << data if op != DIFF_INSERT }
    text
  end

  # Compute and return the destination text (all equalities and insertions).
  def diff_text2(diffs)
    text = +''
    diffs.each { |(op, data)| text << data if op != DIFF_DELETE }
    text
  end

  # Compute the Levenshtein distance; the number of inserted, deleted or
  # substituted characters.
  def diff_levenshtein(diffs)
    levenshtein = 0
    insertions = 0
    deletions = 0
    diffs.each do |(op, data)|
      case op
      when DIFF_INSERT
        insertions += data.length
      when DIFF_DELETE
        deletions += data.length
      when DIFF_EQUAL
        # A deletion and an insertion is one substitution.
        levenshtein += [insertions, deletions].max
        insertions = 0
        deletions = 0
      end
    end
    levenshtein + [insertions, deletions].max
  end

  # Crush the diff into an encoded string which describes the operations
  # required to transform text1 into text2.
  # E.g. =3\t-2\t+ing  -> Keep 3 chars, delete 2 chars, insert 'ing'.
  # Operations are tab-separated.  Inserted text is escaped using %xx notation.
  def diff_to_delta(diffs)
    text = diffs.map do |(op, data)|
      case op
      when DIFF_INSERT then "+#{JsString.encode_uri(data)}"
      when DIFF_DELETE then "-#{data.length}"
      when DIFF_EQUAL then "=#{data.length}"
      end
    end
    text.join("\t").gsub('%20', ' ')
  end

  # Given the original text1, and an encoded string which describes the
  # operations required to transform text1 into text2, compute the full diff.
  def diff_from_delta(text1, delta)
    diffs = []
    pointer = 0 # Cursor in text1
    tokens = delta.split("\t", -1)
    tokens.each do |token|
      # Each token begins with a one character parameter which specifies the
      # operation of this token (delete, insert, equality).
      param = JsString.substring(token, 1)
      case JsString.char_at(token, 0)
      when '+'
        begin
          diffs << create_diff(DIFF_INSERT, JsString.decode_uri(param))
        rescue JsString::UriError
          # Malformed URI sequence.
          raise Error, "Illegal escape in diff_fromDelta: #{param}"
        end
      when '-', '='
        n = JsString.parse_int(param)
        raise Error, "Invalid number in diff_fromDelta: #{param}" if n.nil? || n.negative?

        text = JsString.substring(text1, pointer, pointer + n)
        pointer += n
        if token[0] == '='
          diffs << create_diff(DIFF_EQUAL, text)
        else
          diffs << create_diff(DIFF_DELETE, text)
        end
      else
        # Blank tokens are ok (from a trailing \t).
        # Anything else is an error.
        raise Error, "Invalid diff operation in diff_fromDelta: #{token}" unless token.empty?
      end
    end
    if pointer != text1.length
      raise Error, "Delta length (#{pointer}) does not equal source text length (#{text1.length})."
    end

    diffs
  end
end
