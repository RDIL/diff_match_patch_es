# frozen_string_literal: true

require 'json'
require_relative '../lib/diff_match_patch_es'

dir = __dir__
cases = JSON.parse(File.read(File.join(dir, 'cases.json')))

def run(c)
  r = {}
  opts_fast = { diff_timeout: 60 }
  opts_exact = { diff_timeout: 0 }

  r['diff_exact'] = DiffMatchPatchES.diff_main(c['text1'], c['text2'], opts_exact)
  r['diff_fast'] = DiffMatchPatchES.diff_main(c['text1'], c['text2'], opts_fast)
  r['diff_nolines'] = DiffMatchPatchES.diff_main(c['text1'], c['text2'], opts_fast, false)

  sem = DiffMatchPatchES.diff_main(c['text1'], c['text2'], opts_fast)
  DiffMatchPatchES.diff_cleanup_semantic(sem)
  r['semantic'] = sem

  eff = DiffMatchPatchES.diff_main(c['text1'], c['text2'], opts_fast)
  DiffMatchPatchES.diff_cleanup_efficiency(eff, opts_fast)
  r['efficiency'] = eff

  r['delta'] = DiffMatchPatchES.diff_to_delta(r['diff_fast'])
  r['from_delta'] = DiffMatchPatchES.diff_from_delta(c['text1'], r['delta'])
  r['levenshtein'] = DiffMatchPatchES.diff_levenshtein(r['diff_fast'])
  r['x_index'] = DiffMatchPatchES.diff_x_index(r['diff_fast'], c['loc'])
  r['pretty_html'] = DiffMatchPatchES.diff_pretty_html(r['diff_fast'])
  r['text1'] = DiffMatchPatchES.diff_text1(r['diff_fast'])
  r['text2'] = DiffMatchPatchES.diff_text2(r['diff_fast'])

  patches = DiffMatchPatchES.patch_make(c['text1'], c['text2'], nil, opts_fast)
  r['patch_text'] = DiffMatchPatchES.patch_to_text(patches)
  r['patch_roundtrip'] = DiffMatchPatchES.patch_to_text(DiffMatchPatchES.patch_from_text(r['patch_text']))
  r['patch_apply'] = DiffMatchPatchES.patch_apply(patches, c['text3'], opts_fast)
  r['patch_apply_self'] = DiffMatchPatchES.patch_apply(patches, c['text1'], opts_fast)

  begin
    r['match'] = DiffMatchPatchES.match_main(c['text3'], c['pattern'], c['loc'])
  rescue DiffMatchPatchES::Error => e
    r['match'] = "error: #{e.message}"
  end
  r
end

results = cases.map { |c| run(c) }
File.write(File.join(dir, 'rb_results.json'), JSON.generate(results))
puts "ran #{cases.length} cases"
