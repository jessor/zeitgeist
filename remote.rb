# todo:
# - more documentation
# - logging!
# - ...
require 'mechanize' # for scraping of meta data and image url
require 'open-uri' # for the chunked downloading

class RemoteImageException < Exception
end

# just add more features if plugins need them
class RemotePlugin
  def initialize(url)
    @url = url
  end

  def url
    @url
  end

  def img_url # thats the default behaviour (remote url == image url)
    @url
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
    end
    @agent
  end

  def get(url=@url)
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
      if result and result[0]
        return result[0].content
      else
        raise RemoteImageException.new(
          "url scraping failed parsing of '#{selector}' for #{@url}")
      end
    end

    return ''
  end

end

# include plugins
Dir[File.dirname(__FILE__) + '/remoteplugins/*.rb'].map do |pluginfile|
  require pluginfile
end

class RemoteImage
  attr_reader :url, :img_url, :mimetype, :filesize, :tags, :title, :tempfile

  def initialize(url)
    @plugin = self.class::select_plugin(url).new url
    puts "selected plugin: #{@plugin.class.to_s}"
    @url = url # the plugin may change the url
    @img_url = @plugin.img_url
    puts "plugin scraped img_url: #{img_url}"
    @tags = @plugin.tags
    @title = @plugin.title

    # check to see if the img_url matches against other plugins (bit.ly etc.)

    download
  end

  def self.select_plugin(url)
    RemotePlugins.constants.each do |const|
      plugin = RemotePlugins.const_get(const)
      return plugin if plugin.class == Class and 
          plugin.kind_of? RemotePlugin.class and 
          plugin::PATTERN.match url
    end
    return RemotePlugin
  end

  private

  CHUNK = 16 * 1024
  TEMP_PATH = '/tmp'
  MAX_FILESIZE = 1024 * 1024 * 5
  IMAGE_SIGNATURE = {
    :jpeg => "\xFF\xD8",
    :gif => "\x47\x49\x46",
    :png => "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a"
  }
  def download
    # generate temp name:
    begin
      @tempfile = "#{TEMP_PATH}/zeitgeist-remote-#{Time.now.strftime("%y%m%d%H%M%S")}-#{rand(100)}"
    end while File.exists? @tempfile

    # check the received content length
    content_length_proc = Proc.new do |content_length|
      if content_length and content_length > MAX_FILESIZE
        raise RemoteImageException.new(
            "download error, header indicated content length is too " +
            "large (#{content_length}, max: #{MAX_FILESIZE})")
      end
    end
    # TODO: should also check the received content type

    puts "fetch #{@img_url}"
    begin
      open(@img_url, 'r', :content_length_proc => content_length_proc) do |input|
        # first read the image header/signature to verify image
        # very preliminary test, but doesnt really matter
        max_sigsize = IMAGE_SIGNATURE.values.max { |a, b| a.length <=> b.length }.length
        puts "input read #{max_sigsize} bytes"
        sigcontent = input.read(max_sigsize)
        if not sigcontent
          raise RemoteImageException.new("cannot read from remote url")
        end
        puts sigcontent.inspect
        IMAGE_SIGNATURE.each_pair do |type, sig|
          if sigcontent[0...sig.length] == sig
            @mimetype = "image/#{type.to_s}"
            break
          end
        end 
        if not @mimetype
          raise RemoteImageException.new("unable to determine image type")
        end

        # read/write remote image in chunks to temp file
        @filesize = sigcontent.length
        temp = open(@tempfile, 'wb')
        temp.write(sigcontent)
        while chunk = input.read(CHUNK)
          @filesize += temp.write(chunk)
          if @filesize > MAX_FILESIZE
            raise RemoteImageException.new(
              "cannot write anymore data, image is larger than maximum (#{@filesize}, #{MAX_FILESIZE})")
          end
        end
        temp.close
      end # end uri-open
    rescue OpenURI::HTTPError => e
      raise RemoteImageException.new(
        "http error occured, downloading remote url (#{@img_url}) failed: #{e.message}")
    rescue URI::InvalidURIError => e
      raise RemoteImageException.new(
        "looks like an invalid url (#{@img_url}), failed: #{e.message}")
    end
  end 
end


