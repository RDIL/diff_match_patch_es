# frozen_string_literal: true

require 'json'

dir = __dir__
js = JSON.parse(File.read(File.join(dir, 'js_results.json')))
rb = JSON.parse(File.read(File.join(dir, 'rb_results.json')))
cases = JSON.parse(File.read(File.join(dir, 'cases.json')))

abort "length mismatch: #{js.length} vs #{rb.length}" unless js.length == rb.length

mismatches = 0
js.each_with_index do |jres, i|
  rres = rb[i]
  next if jres == rres

  mismatches += 1
  puts "=== case #{i} mismatch ==="
  puts "input: #{cases[i].inspect[0, 300]}"
  jres.each_key do |k|
    next if jres[k] == rres[k]

    puts "  key #{k}:"
    puts "    js: #{jres[k].inspect[0, 400]}"
    puts "    rb: #{rres[k].inspect[0, 400]}"
  end
  break if mismatches >= 5
end

if mismatches.zero?
  puts "PARITY OK: all #{js.length} cases identical"
else
  abort "#{mismatches}+ mismatching cases"
end
