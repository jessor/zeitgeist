
class Soundcloud < Plugin
  TYPE = 'audio'
  PATTERN = %r{^http[s]?://soundcloud\.com/[\S]+/[\S]+}

  def url
    nil # prevent downloading (there is no preview image)
  end

  def title
    og_search 'title'
  end

  def tags
    search '.tag-list a .tag/text()'
  end

  def embed
    OEmbed::Provider.new('http://soundcloud.com/oembed').get(@orig_url).html
  end
end

