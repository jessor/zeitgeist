
class Vimeo < Plugin
  TYPE = 'video'
  PATTERN = 'vimeo.com'
  # PATTERN = %r{http[s]?://(www\.)?vimeo\.com/}

  def filename
    self.title.gsub(/[^a-zA-Z0-9_\-\.]/, '')
  end

  def url # return url to preview image
    match_one /thumbs: {\d+: '([^']+)'/
  end

  def title
    og_search 'title'
  end

  def tags
    search '.tags li a/text()'
  end
end

