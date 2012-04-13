# Fingerprint Generation Script for Zeitgeist
# -------------------------------------------
# This script generates pHash fingerprints for all image
# items in zeitgeist.
#

puts 'Usage: %s [-f]' % $0
puts ' -f    override existing hashes'
if ARGV.include? '-f'
  override = true
end

Dir.chdir File.join(File.dirname(__FILE__), '..')
require_relative '../zeitgeist.rb'

params = {:type => 'image'}
if not override
  params.merge(:fingerprint.not => nil)
end

total = Item.count(params)
start = Time.now
current = 1
puts 'generating %d fingerprints' % total
Item.all(params).each do |item|
  fingerprint = item.generate_fingerprint
  item.update(:fingerprint => fingerprint)
  eta = (((Time.now - start) / current) * (total - current)) / 60
  print "calculating %05d/%05d [ETA:%dmin]\r" % [current, total, eta.to_i]
  current+=1
end

