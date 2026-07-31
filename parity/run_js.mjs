import { readFileSync, writeFileSync } from 'node:fs'
import {
  diffMain, diffCleanupSemantic, diffCleanupEfficiency, diffToDelta,
  diffFromDelta, diffLevenshtein, diffXIndex, diffPrettyHtml, diffText1,
  diffText2, patchMake, patchToText, patchApply, patchFromText, matchMain,
} from 'diff-match-patch-es'

const cases = JSON.parse(readFileSync(new URL('./cases.json', import.meta.url), 'utf8'))

function run(c) {
  const r = {}
  const optsFast = { diffTimeout: 60 }
  const optsExact = { diffTimeout: 0 }

  r.diff_exact = diffMain(c.text1, c.text2, optsExact)
  r.diff_fast = diffMain(c.text1, c.text2, optsFast)
  r.diff_nolines = diffMain(c.text1, c.text2, optsFast, false)

  const sem = diffMain(c.text1, c.text2, optsFast)
  diffCleanupSemantic(sem)
  r.semantic = sem

  const eff = diffMain(c.text1, c.text2, optsFast)
  diffCleanupEfficiency(eff, optsFast)
  r.efficiency = eff

  r.delta = diffToDelta(r.diff_fast)
  r.from_delta = diffFromDelta(c.text1, r.delta)
  r.levenshtein = diffLevenshtein(r.diff_fast)
  r.x_index = diffXIndex(r.diff_fast, c.loc)
  r.pretty_html = diffPrettyHtml(r.diff_fast)
  r.text1 = diffText1(r.diff_fast)
  r.text2 = diffText2(r.diff_fast)

  const patches = patchMake(c.text1, c.text2, undefined, optsFast)
  r.patch_text = patchToText(patches)
  r.patch_roundtrip = patchToText(patchFromText(r.patch_text))
  r.patch_apply = patchApply(patches, c.text3, optsFast)
  r.patch_apply_self = patchApply(patches, c.text1, optsFast)

  try {
    r.match = matchMain(c.text3, c.pattern, c.loc)
  }
  catch (e) {
    r.match = `error: ${e.message}`
  }
  return r
}

const results = cases.map(run)
writeFileSync(new URL('./js_results.json', import.meta.url), JSON.stringify(results))
console.log(`ran ${cases.length} cases`)
