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

require File.dirname(File.expand_path(__FILE__)) + '/plugins.rb'

module Sinatra
module Remote

class RemoteException < Exception
end

class Downloader
  attr_reader :tempfile, :mimetype, :filesize 

  def initialize(url)
    @url = url
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
      @tempfile = "#{settings.remote_temp}/zg-remote-" + 
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
      end,
      'User-Agent' => settings.agent
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

    puts "fetch #{@url}"
    begin
      open(@url, 'r', open_args) do |input|
        # first read the image header/signature to verify image
        # very preliminary test, but doesnt really matter
        max_sigsize = IMAGE_SIGNATURE.values.max { |a, b| a.length <=> b.length }.length
        sigcontent = input.read(max_sigsize)
        if not sigcontent
          raise RemoteException.new("cannot read from remote url")
        end
        IMAGE_SIGNATURE.each_pair do |mime, sig|
          header = sigcontent[0...sig.length]
          begin #only effects 2.0.0
          header.force_encoding('ASCII-8BIT')
          sig.force_encoding('ASCII-8BIT')
          rescue
          end
          if header == sig
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
  app.set :temppath => '/tmp'
  app.set :remote_chunk => 1024 * 128 # 128 KiB
  app.set :remote_max_filesize => 1024 ** 2 * 8 # 8 MiB
  app.set :remote_proxy_host => nil
  app.set :remote_proxy_port => nil
  app.set :remote_proxy_user => nil
  app.set :remote_proxy_pass => nil

  # initialize oembed
  # used in plugin.embed as the default behaviour
  OEmbed::Providers.register_all
end

end # end namespace Remote

# register zeitgeist remote as sinatra extension
register Remote

end # end namespace Sinatra

