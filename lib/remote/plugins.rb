
module Sinatra::ZeitgeistRemote

module Plugins
  # iterate all classes within Plugins namespace and test url
  # for matching PATTERN:
  def self.plugin_by_url(url)
    return nil if not url =~ URI::regexp
    Plugins::constants.each do |const|
      plugin = Plugins::const_get(const)
      return plugin.new(url) if plugin.class == Class and 
          plugin.kind_of? Plugin.class and 
          plugin::PATTERN.match url
    end
    return Plugin.new(url) # default plugin
  end
end

# Default Plugin for pre-download processing
# This plugin is used for all urls with the exception of urls
# that are matched by an plugin pattern (plugin constant PATTERN)
# Plugins for specific sites may scrape for the real image
# url and/or for other content like tags or titles.
class Plugin
  TYPE = 'image' 

  # initialize with the original remote url
  # this default plugin assumes an image/ resource
  def initialize(orig_url)
    @orig_url = orig_url
  end

  def type
    self.class::TYPE
  end

  # original url (can point to html page)
  def orig_url
    @orig_url
  end

  # should return url to an image/png,jpg,gif file
  # or nil if there isn't one (image/audio without preview pic)
  def url
    # defines the default behaviour: no change in remote image url
    # other remote plugins may overwrite this behaviour and scrape
    # the image link from html (along other information)
    @orig_url
  end

  # the extracted content title or original filename
  def title
    path = URI.parse(url).path
    filename = File.basename(path)
    return filename.gsub('/', '')
  end

  def tags
    []
  end

  def embed
    OEmbed::Providers.get(@orig_url).html
  end

  private

  # allow plugins to use mechanize for scraping urls, tags etc.
  def agent
    if not @agent
      @agent = Mechanize.new
      if settings.remote_proxy_host
        @agent.set_proxy(
          settings.remote_proxy_host,
          settings.remote_proxy_port, 
          settings.remote_proxy_user, 
          settings.remote_proxy_pass 
        )
      end
    end
    @agent
  end

  def get(url = nil)
    url = self.orig_url if not url
    if not @page
      puts "get url: #{url}"
      @page = agent.get url
    end
    @page
  end

  def scan(pattern)
    # implicit fetch the page of the url
    get if not @page
    return if not @page

    result = @page.body.scan pattern
    if not result or result.empty?
      puts "url scraping failed regex matching of '#{pattern}' for #{@url}"
      return []
    end

    puts "search result for #{pattern} : #{result.inspect}"

    return result
  end

  def match(pattern)
    scan(pattern).first || []
  end

  def match_one(pattern)
    match(pattern).first || ''
  end

  def search(selector)
    # implicit fetch the page of the url
    get if not @page
    return if not @page

    result = @page.search selector
    if not result
      puts "url scraping failed parsing of '#{selector}' for #{@url}"
      return []
    end

    puts "search selector #{selector}: #{result.inspect}"
    return [] if result.length == 0

    # convert to simple array of strings
    result = result.map do |elem|
      case elem
      when Nokogiri::XML::Text
        elem.content
      when Nokogiri::XML::Attr
        elem.value
      else
        elem
      end
    end

    return result
  end

  def search_one(selector)
    search(selector).first || '' 
  end

  def og_search(property)
    search_one 'meta[@property="og:' + property + '"]/@content' 
  end

end # end class plugin

# dynamically include plugins
Dir[File.dirname(__FILE__) + '/plugins/*.rb'].map do |pluginfile|
  require pluginfile
end

end # Sinatra::Remote

