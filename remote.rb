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

module Sinatra
module ZeitgeistRemote

class RemoteException < Exception
end

module Plugins
end

# Default Plugin for pre-download processing
# This plugin is used for all urls with the exception of urls
# that are matched by an plugin pattern (plugin constant PATTERN)
# Plugins for specific sites may scrape for the real image
# url and/or for other content like tags or titles.
class Plugin
  def initialize(orig_url)
    @orig_url = orig_url
  end

  # original url (can point to html page)
  def orig_url
    @orig_url
  end

  # should return url to an image/png,jpg,gif file
  def url
    # defines the default behaviour: no change in remote image url
    @orig_url
  end

  def title
    nil
  end

  def tags
    []
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
      @page = agent.get url
    end
    @page
  end

  def search(selector)
    if not @page
      # implicit fetch the page of the url
      @page = get
    end

    if @page
      result = @page.search selector
      if result
        if result.length == 1
          return result[0].content
        else
          return result
        end
      else
        raise RemoteException.new(
          "url scraping failed parsing of '#{selector}' for #{@url}")
      end
    end

    return ''
  end

end # end class plugin

class ImageDownloader
  attr_reader :orig_url, :url, :tempfile, :mimetype, :filesize, :tags, :title 

  def initialize(orig_url)
    @orig_url = orig_url

    # dynamically instanciate plugin based on orig_url
    @plugin = select_plugin.new orig_url

    puts "selected plugin: #{@plugin.class.to_s}"

    # specific site plugins may scrape for the correct values:
    begin
      @url = @plugin.url # default: the same as orig_url
      @tags = @plugin.tags # []
      @title = @plugin.title # nil
    rescue Exception => e
      # do not fail just yet,
      # log the exception and try with the original url
      puts "plugin failure: #{e.message}"
      @url = @orig_url
      @tags = []
      @title = []
    end

    download
  end

  # iterate all classes within Plugins namespace and test orig_url
  # for matching PATTERN:
  def select_plugin
    Plugins::constants.each do |const|
      plugin = Plugins::const_get(const)
      return plugin if plugin.class == Class and 
          plugin.kind_of? Plugin.class and 
          plugin::PATTERN.match @orig_url
    end
    return Plugin # default plugin
  end

  private

  IMAGE_SIGNATURE = {
    'image/jpeg' => "\xFF\xD8",
    'image/gif' => "\x47\x49\x46",
    'image/png' => "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a"
  }

  # Download the image using open-uri
  # Performs a simple header/signature test before downloading
  # the complete image. Writes a temporary file and sets mime
  # and filesize attributes.
  def download
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

    puts "fetch #{@url}"
    begin
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

      open(@url, 'r', open_args) do |input|
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
        "http error occured, downloading remote url (#{@url}) failed: #{e.message}")
    rescue URI::InvalidURIError => e
      raise RemoteException.new(
        "looks like an invalid url (#{@url}), failed: #{e.message}")
    rescue Exception => e
      raise RemoteException.new(
        "something went wrong during downloading of url (#{@url}): #{e.message}")
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

