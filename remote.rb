# sinatra extension for remote image downloading
#
# to use this extension require the remote.rb file within the sinatra
# app and use Sinatra::ZeitgeistRemote::ImageDownloader.new(url) for
# remote image downloading. For more usage consider remote_test.rb
#
# todo:
# - more documentation
# - logging!
# - ...
require 'sinatra/base'
require 'mechanize' # for scraping of meta data and image url
require 'open-uri' # for the chunked downloading
require 'uri'

module Sinatra
module ZeitgeistRemote

class RemoteException < Exception
end

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
    if result.empty?
      raise RemoteException.new(
        "url scraping failed regex matching of '#{pattern}' for #{@url}")
    end

    puts "search result for #{pattern} : #{result.inspect}"

    return result
  end

  def match(pattern)
    scan(pattern).first
  end

  def match_one(pattern)
    match(pattern).first
  end

  def search(selector)
    # implicit fetch the page of the url
    get if not @page
    return if not @page

    result = @page.search selector
    if not result
      raise RemoteException.new(
        "url scraping failed parsing of '#{selector}' for #{@url}")
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
    search(selector).first
  end

  def og_search(property)
    search_one 'meta[@property="og:' + property + '"]/@content'
  end

end # end class plugin

class RemoteDownloader
  attr_reader :plugin, :type, :tempfile, :mimetype, :filesize 

  def initialize(plugin)
    plugin = Plugins::plugin_by_url(plugin) if plugin.class == String
    @plugin = plugin
    @type = @plugin.class::TYPE
    @tempfile = nil
    @mimetype = nil
    @filesize = nil
  end

  IMAGE_SIGNATURE = {
    'image/jpeg' => "\xFF\xD8",
    'image/gif' => "\x47\x49\x46",
    'image/png' => "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a"
  }

  # Download the image using open-uri
  # Performs a simple header/signature test before downloading
  # the complete image. Writes a temporary file and sets mime
  # and filesize attributes.
  def download!
    # generate temp name:
    begin
      @tempfile = "#{settings.remote_temp_path}/zeitgeist-remote-" + 
        "#{Time.now.strftime("%y%m%d%H%M%S")}-#{rand(100)}"
    end while File.exists? @tempfile

    # check the received content length
    open_args = {
      :content_length_proc => Proc.new do |content_length|
        if content_length and content_length > settings.remote_max_filesize
          raise RemoteException.new(
              "download error, header indicated content length is too " +
              "large (#{content_length}, max: #{settings.remote_max_filesize})")
        end
      end
    }
    # TODO: should also check the received content type

    if settings.remote_proxy_host
      proxy_uri = "http://#{settings.remote_proxy_host}:#{settings.remote_proxy_port}/"
      if settings.remote_proxy_user
        open_args[:proxy_http_basic_authentication] = [
          proxy_uri, settings.remote_proxy_user, settings.remote_proxy_pass
        ]
      else
        open_args[:proxy] = proxy_uri
      end
    end

    puts "fetch #{@plugin.url}"
    begin
      open(@plugin.url, 'r', open_args) do |input|
        # first read the image header/signature to verify image
        # very preliminary test, but doesnt really matter
        max_sigsize = IMAGE_SIGNATURE.values.max { |a, b| a.length <=> b.length }.length
        puts "input read #{max_sigsize} bytes"
        sigcontent = input.read(max_sigsize)
        if not sigcontent
          raise RemoteException.new("cannot read from remote url")
        end
        puts sigcontent.inspect
        IMAGE_SIGNATURE.each_pair do |mime, sig|
          if sigcontent[0...sig.length] == sig
            @mimetype = mime
            break
          end
        end 
        if not @mimetype
          raise RemoteException.new("no image signature found")
        end

        # read/write remote image in chunks to temp file
        @filesize = sigcontent.length
        temp = open(@tempfile, 'wb')
        temp.write(sigcontent)
        while chunk = input.read(settings.remote_chunk)
          @filesize += temp.write(chunk)
          if @filesize > settings.remote_max_filesize
            raise RemoteException.new(
              "cannot write anymore data, image is larger than maximum " + 
              "(#{@filesize}, #{settings.remote_max_filesize})")
          end
        end
        temp.close
      end # end uri-open
    rescue OpenURI::HTTPError => e
      raise RemoteException.new(
        "http error occured, downloading remote url (#{@plugin.url}) failed: #{e.message}")
    rescue URI::InvalidURIError => e
      raise RemoteException.new(
        "looks like an invalid url (#{@plugin.url}), failed: #{e.message}")
    rescue Exception => e
      raise RemoteException.new(
        "something went wrong during downloading of url (#{@plugin.url}): #{e.message}")
    end
  end 
end

# set default configuration
def self.registered(app)
  app.set :remote_chunk => 1024 * 16 # 16 KiB
  app.set :remote_temp_path => '/tmp'
  app.set :remote_max_filesize => 1024 ** 2 * 8 # 8 MiB
  app.set :remote_proxy_host => nil
  app.set :remote_proxy_port => nil
  app.set :remote_proxy_user => nil
  app.set :remote_proxy_pass => nil
end

end # end namespace ZeitgeistRemote

# register zeitgeist remote as sinatra extension
register ZeitgeistRemote

end # end namespace Sinatra

# dynamically include plugins
Dir[File.dirname(__FILE__) + '/remoteplugins/*.rb'].map do |pluginfile|
  require pluginfile
end

