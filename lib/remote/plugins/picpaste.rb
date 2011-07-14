
class Picpaste < Plugin
  TYPE = 'image'
  PATTERN = %r{http://(www\.)?picpaste\.com}

  def url
    'http://picpaste.com' + search_one('.picture a[1]/@href')
  end
end

