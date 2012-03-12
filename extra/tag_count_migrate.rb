
Dir.chdir File.join(File.dirname(__FILE__), '..')

require_relative '../zeitgeist.rb'

Tag.all.each do |tag|
  count = ItemTag.count(:tag => tag)
  tag.update(:count => count)
  puts "Updated count of \"%s\" to %d" % [tag.tagname, count]
end

