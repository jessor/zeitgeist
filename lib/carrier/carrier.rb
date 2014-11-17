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

  module VideoProcessor
    # returns a <width>x<height> string of the video dimensions
    def video_dimensions(file)
      dimensions = nil
      IO.popen('ffmpeg -i %s 2>&1' % file, 'r') do |io|
        io.each do |line|
          if line.match /Video: .* (\d+x\d+)/
            dimensions = $1
          end
        end
      end
      return dimensions
    end

    # returns the (temporary) thumbnail of the video generated using ffmpeg
    def video_thumbnail(file)
      # generate temp name for thumbnail
      begin
        thumbnail = "#{settings.carrier[:temp]}/zg-carrier-" + 
          "#{Time.now.strftime("%y%m%d%H%M%S")}-#{rand(100)}.jpg"
      end while File.exists? thumbnail

      IO.popen('ffmpeg -i %s -vframes 1 %s 2>&1' % [file, thumbnail], 'r') do |io|
        io.readlines
      end
      thumbnail
    end
  end

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

    def image_thumbnail!(image, width, height=nil)
      img = ::MiniMagick::Image.open(image)

      img.collapse!
      cols, rows = img['dimensions']
      ratio = cols / rows.to_f

      # no thumbnail (image is smaller than thumb)
      return nil if width > cols and width != height

      if not height # set height in relation to aspect
        height = width / ratio 
        height = rows if height > rows
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
    include VideoProcessor

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

      # video/webm needs some special handling:
      if @mimetype == 'video/webm'
        @dimensions = video_dimensions(@image)
        @animated = true

        # creates a video thumbnail using ffmpeg:
        thumbnail_base = video_thumbnail(@image)
      else
        # figure out dimensions&animation
        img = ::MiniMagick::Image.open(image)
        @dimensions = image_dimensions(img)
        @animated = image_animated?(img)

        thumbnail_base = @image
      end

      # create thumbnails, the hash stores the size(as key)+temp local path
      @thumbnails = {
        '200' => image_thumbnail!(thumbnail_base, 200, 200), # 200 squared
        '480' => image_thumbnail!(thumbnail_base, 480) # sets height based on ratio
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
  end

end # Carrier

register Carrier

end # Sinatra

