
class Picpaste < Plugin
  TYPE = 'image'
  PATTERN = %r{http://(www\.)?picpaste\.com}

  def url
    path = search_one('.picture a[1]/@href') 
    ('http://picpaste.com' + path) if path
  end
end

