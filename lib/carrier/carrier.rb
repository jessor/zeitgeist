#
# we use this as a replacement for carrierwave that as it turned out was
# not flexible enough to suffice our requirements.
#
require 'sinatra/base'

# create a bundle group or something like that for each lib
# so that we can call something like: Bundler.require(:carrier)
require 'mini_magick'

require File.dirname(File.expand_path(__FILE__)) + '/storage.rb'

module Sinatra

module Carrier

  # some functions that help with image detection and manipulation
  module ImageProcessor
    # we want to: find the dimension, find out if this is multiple
    # frame gif, if yes collapse it and resize to fill
    
    # return mimetype and file extension
    def image_mimetype(image)
      mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(image)
      mimetype = mimetype.slice 0...mimetype.index(';')
      raise 'invalid mimetype' if not settings.allowed_mime.include? mimetype
      [mimetype, mimetype.split('/').last]
    end

    def image_dimensions(img)
      dimensions = img['%wx%h\n']
      if dimensions.match /\d+x\d+/
        dimensions
      else
        ''
      end
    end

    def image_animated?(img)
      frames = img['%w,'].strip
      frames.slice!(-1)
      if not frames or frames.split(',').length <= 1
        false
      else
        true
      end
    end

    def image_thumbnail!(image, width, &block)
      img = ::MiniMagick::Image.open(image)

      # NOTE: should only be used to identify the image:
      yield(img) if block

      img.collapse!
      cols, rows = img['dimensions']
      ratio = cols / rows.to_f

      if width == 200
        height = 200
      else # 480x? in relation to aspect
        height = width / ratio 
      end

      img.combine_options do |cmd|
        if width != cols || height != rows
          scale = [width/cols.to_f, height/rows.to_f].max
          cols = (scale * (cols + 0.5)).round
          rows = (scale * (rows + 0.5)).round
          cmd.resize "#{cols}x#{rows}"
        end
        cmd.gravity 'Center'
        cmd.extent "#{width}x#{height}" if cols != width || rows != height
      end

      # generate temp name for thumbnail
      begin
        thumbnail = "#{settings.carrier[:temp]}/zg-carrier-" + 
          "#{Time.now.strftime("%y%m%d%H%M%S")}-#{rand(100)}"
      end while File.exists? thumbnail

      img.write(thumbnail)
      # img doesnt need cleanup?
    
      return thumbnail
    rescue ::MiniMagick::Error, ::MiniMagick::Invalid
      raise 'image processing error: ' + $!
    end

    def remove_exif!(image)
      img = ::MiniMagick::Image.open(image)
      img.strip
      img.write(image)
    end
  end

  # all files are processed locally at a temporary location first,
  # regardless of the storage engine used later
  class LocalTemp
    include ImageProcessor

    attr_reader :image, :thumbnails, :checksum, :mimetype, :dimensions, :animated
    attr_reader :md5obj, :created_at, :extension

    # created_at is used for the storage directories
    def initialize(image, created_at=Time.now)
      @image = image # image is the temporary file from upload/remote download
      @created_at = created_at
    end

    # stat filesize only if necessary! thats why this is an
    # extra method instead of a attribute that is set within
    # process! because remote already knows how many bytes
    # it has written.
    # Filesize validation makes no sense here, either sinatra
    # file upload itself needs to be limited, or the remote
    # fetcher should throw an error (it does).
    def filesize
      File.size(@image)
    end

    def process!
      raise 'file not found!' if not File.exists? @image

      # mimetype detection and validation
      @mimetype, @extension = image_mimetype @image

      # remove exif data if jpeg:
      if @mimetype.include? 'jpeg'
        remove_exif!(@image)
      end

      # calculate md5 sum
      @md5obj = Digest::MD5.file(@image)
      @checksum = @md5obj.hexdigest

      # create thumbnails, the hash stores the size(as key)+temp local path
      @thumbnails = {
        '200' => image_thumbnail!(@image, 200) do |img|
          @dimensions = image_dimensions(img)
          @animated = image_animated?(img)
        end,
        # '480' => image_thumbnail!(@image, 480)
      }
    end

    def store!
      # this moves the temporary images to their final destination (see Store)
      store = Store.new
      store.store! self
    end

    # it should be ensured that this is always beeing called,
    # even if an error occurred!
    def cleanup!
      File.unlink @image if @image and File.exists? @image
      @thumbnails.values.each do |thumbnail|
        File.unlink thumbnail if thumbnail and File.exists? thumbnail
      end if @thumbnails
    end
  end

  # register carrier as a sinatra plugin
  def self.registered(app)
    # app.set :carrier => {
    #   # temporary directory, used for thumbnail creation:
    #   :temp => '/tmp',
    #   :store => 'local',
    #   :local => {
    #     :path => './public/asset',
    #     :url_base => '/asset'
    #   }
    # }
  end

end # Carrier

register Carrier

end # Sinatra

