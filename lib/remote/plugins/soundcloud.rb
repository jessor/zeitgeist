
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

  def embed(width=640, height=385)
    OEmbed::Provider.new('http://soundcloud.com/oembed').get(@orig_url, :maxwidth=>width, :maxheight=>height).html
  end
end

