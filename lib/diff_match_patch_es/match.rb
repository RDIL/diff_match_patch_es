# frozen_string_literal: true

module DiffMatchPatchES
  # JS bitwise operators coerce to 32-bit integers; Ruby integers are
  # arbitrary precision, so shifts are masked to keep the two congruent.
  MASK32 = 0xFFFFFFFF
  private_constant :MASK32

  module_function

  # Locate the best instance of 'pattern' in 'text' near 'loc'.
  # Returns the best match index or -1.
  def match_main(text, pattern, loc, options = nil)
    # Check for null inputs.
    raise Error, 'Null input. (match_main)' if text.nil? || pattern.nil? || loc.nil?

    loc = loc.clamp(0, text.length)
    if text == pattern
      # Shortcut (potentially not guaranteed by the algorithm)
      0
    elsif text.empty?
      # Nothing to match.
      -1
    elsif JsString.substring(text, loc, loc + pattern.length) == pattern
      # Perfect match at the perfect spot!  (Includes case of null pattern)
      loc
    else
      # Do a fuzzy compare.
      match_bitap(text, pattern, loc, options)
    end
  end

  # Locate the best instance of 'pattern' in 'text' near 'loc' using the
  # Bitap algorithm.
  def match_bitap(text, pattern, loc, options = nil)
    resolved = resolve_options(options)

    raise Error, 'Pattern too long for this browser.' if pattern.length > resolved.match_max_bits

    # Initialise the alphabet.
    s = match_alphabet(pattern)

    # Compute and return the score for a match with e errors and x location.
    # (0.0 = good, 1.0 = bad)
    bitap_score = lambda do |e, x|
      accuracy = e.fdiv(pattern.length)
      proximity = (loc - x).abs
      if resolved.match_distance.zero?
        # Dodge divide by zero error.
        return proximity.zero? ? accuracy : 1.0
      end
      accuracy + proximity.fdiv(resolved.match_distance)
    end

    # Highest score beyond which we give up.
    score_threshold = resolved.match_threshold
    # Is there a nearby exact match? (speedup)
    best_loc = JsString.index_of(text, pattern, loc)
    if best_loc != -1
      score_threshold = [bitap_score.call(0, best_loc), score_threshold].min
      # What about in the other direction? (speedup)
      best_loc = JsString.last_index_of(text, pattern, loc + pattern.length)
      score_threshold = [bitap_score.call(0, best_loc), score_threshold].min if best_loc != -1
    end

    # Initialise the bit arrays.
    matchmask = (1 << (pattern.length - 1)) & MASK32
    best_loc = -1

    bin_max = pattern.length + text.length
    last_rd = []
    d = 0
    while d < pattern.length
      # Scan for the best match; each iteration allows for one more error.
      # Run a binary search to determine how far from 'loc' we can stray at
      # this error level.
      bin_min = 0
      bin_mid = bin_max
      while bin_min < bin_mid
        if bitap_score.call(d, loc + bin_mid) <= score_threshold
          bin_min = bin_mid
        else
          bin_max = bin_mid
        end
        bin_mid = (bin_max - bin_min) / 2 + bin_min
      end
      # Use the result from this iteration as the maximum for the next.
      bin_max = bin_mid
      start = [1, loc - bin_mid + 1].max
      finish = [loc + bin_mid, text.length].min + pattern.length

      rd = Array.new(finish + 2, 0)
      rd[finish + 1] = ((1 << d) - 1) & MASK32
      j = finish
      while j >= start
        char_match = s[JsString.char_at(text, j - 1)] || 0
        rd[j] = if d.zero? # First pass: exact match.
                  (((rd[j + 1] << 1) | 1) & char_match) & MASK32
                else # Subsequent passes: fuzzy match.
                  ((((rd[j + 1] << 1) | 1) & char_match) |
                    ((((last_rd[j + 1] || 0) | (last_rd[j] || 0)) << 1) | 1) |
                    (last_rd[j + 1] || 0)) & MASK32
                end
        if (rd[j] & matchmask) != 0
          score = bitap_score.call(d, j - 1)
          # This match will almost certainly be better than any existing
          # match.  But check anyway.
          if score <= score_threshold
            # Told you so.
            score_threshold = score
            best_loc = j - 1
            if best_loc > loc
              # When passing loc, don't exceed our current distance from loc.
              start = [1, (2 * loc) - best_loc].max
            else
              # Already passed loc, downhill from here on in.
              break
            end
          end
        end
        j -= 1
      end
      # No hope for a (better) match at greater error levels.
      break if bitap_score.call(d + 1, loc) > score_threshold

      last_rd = rd
      d += 1
    end
    best_loc
  end

  # Initialise the alphabet for the Bitap algorithm.
  def match_alphabet(pattern)
    s = {}
    pattern.each_char { |ch| s[ch] = 0 }
    pattern.length.times do |i|
      s[pattern[i]] |= (1 << (pattern.length - i - 1)) & MASK32
    end
    s
  end
end
