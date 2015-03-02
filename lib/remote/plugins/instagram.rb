
class Instagram < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?instagram\.com/[^/]*p/.+}

  def url
    og_search 'image'
  end

  def title
    og_search 'description'
  end
end

