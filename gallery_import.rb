# gallery import script for zeitgeist
require 'mysql'

ENV['RACK_ENV'] = 'production'

require './zeitgeist.rb'

settings = {
  :path => '/home/apoc/code/ruby/zeitgeist/b', 
  :mysql_host => 'localhost',
  :mysql_user => 'changeme',
  :mysql_pass => 'changeme',
  :mysql_base => 'changeme'
}

configure do
  set :delete_tmp_file_after_storage, false
end

def add_item(tempfile, created_at, tags)
  # store in database, the before save hook downloads/proccess the file
  @item = Item.new(:image => tempfile, 
                   :source => File.basename(tempfile), 
                   :created_at => created_at)
  if @item.save
    # successful? append new tags:
    tags.each do |tagname|
      tag = Tag.first_or_create(:tagname => tagname)
      if tag.save
        @item.tags << tag
      else
        raise 'error saving new tag: ' + tag.errors.first
      end
    end
    @item.save # save the new associations
  end
end

# connect to mysql
begin
  db = Mysql.real_connect(settings[:mysql_host], 
                          settings[:mysql_user], 
                          settings[:mysql_pass], 
                          settings[:mysql_base])
rescue Mysql::Error => e
  puts "error connecting to mysql: #{e.error}"
  exit
end

item_results = db.query <<sql
SELECT 
  item.g_id AS id, item.g_title AS title,
  item.g_originationTimestamp AS timestamp, fs.g_pathComponent AS path,
  item.g_canContainChildren, item.g_ownerId
FROM 
  g2_Item AS item
LEFT JOIN
  g2_FileSystemEntity AS fs
ON
  fs.g_id = item.g_id;
sql

gallery_files = Dir["#{settings[:path]}/*"]
gallery_files_len = gallery_files.length

# keep some stats
count = 0
ok = 0
errors = 0
not_found = 0
duplicates = 0

error_log = File.open('gallery_import.log', 'a+')

time_start = Time.now

item_count = item_results.num_rows
item_results.each_hash do |row|
  count += 1
  id = row['id']
  title = row['title']
  timestamp = row['timestamp']
  filename = row['path']
  create_at = Time.at(timestamp.to_i)
  tags = []

  time_duration = Time.now - time_start
  speed = (time_duration.to_f / (ok + errors + duplicates).to_f)
  est = speed * (item_count - count)

  if est > 0 and est != Infinity
    est_string = (Time.at(est.to_i)).strftime("%H:%M:%S")
  else
    est_string = '-'
  end

  percent = (100.0/item_count) * count.to_f

  print "\x1b[2K##{count}[#{id}] <#{'%0.2f' % percent}%> ok:#{ok}/#{item_count} not found:#{not_found} " + 
        " errors:#{errors} dups:#{duplicates} " +
        " (files read:#{gallery_files.length}/#{gallery_files_len}) " +
        " [#{'%0.f' % time_duration} sec EST: #{est_string}]" +
        "\r"

  tempfile = "#{settings[:path]}/#{filename}"

  if not File.exists? tempfile or not File.file? tempfile
    # puts "(#{id}/#{item_count}) [#{row['g_canContainChildren']} || #{row['g_ownerId']}] not existing: #{tempfile} (title: #{title})"
    not_found += 1
    next
  end 

  gallery_files.delete tempfile

  # get tags
  tag_results = db.query <<sql
    SELECT 
      tag.g_tagName AS tag_name
    FROM
      g2_TagMap AS tag
    LEFT JOIN
      g2_TagItemMap AS tag_item
    ON
      tag.g_tagId = tag_item.g_tagId
    WHERE
      tag_item.g_itemId = #{id};
sql
  tag_results.each_hash do |tag|
    tags << tag['tag_name']
  end

  begin
    $stdout = error_log
    add_item(tempfile, create_at, tags)
  rescue Exception => e
    if e.message =~ /Duplicate/
      duplicates += 1
      next
    end
    errors += 1
    error_log.puts "------------- #{tempfile}"
    error_log.puts "Import Error: #{e.message}"
    error_log.puts e.backtrace.join("\n")
    error_log.puts
  else
    ok += 1
  end
  $stdout = STDOUT
end
error_log.close
puts
puts "Duplicates: #{duplicates}"

File.open('gallery_import.pending', 'w').puts gallery_files.join "\n"

db.close if db

