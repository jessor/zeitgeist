
class Dropbox < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?dropbox\.com/}

  def title
    og_search 'title'
  end

  def url
    og_search 'image'
  end
end

