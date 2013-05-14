
module Sinatra::Carrier

  # image object stores year/month directory and filename
  # constructs local system paths and web urls of the image
  # and arbirary thumbnails
  # used in the store objects, also created
  # by the item model.
  # Is not used in localtemp! (note)
  class Image
    attr_accessor :image

    def initialize(image)
      @image = image # like "/201301/zg.foo.jpeg"
    end

    def to_s
      @image
    end

    def web
      Image.new(File.join(settings.carrier[:web_path], @image))
    end

    def local
      Image.new(File.join(settings.carrier[:local_path], @image))
    end

    def exists?
      File.exists?(local.to_s)
    end

    # thumbnail version of the image
    def thumbnail(width)
      Image.new(@image.gsub(/\.(\w+)$/, '_%d.\1' % width))
    end

    def to_json(options)
      {:image => @image}.to_json
    end
  end

  # stores image files from a temporary location
  class Store
    def initialize
      # make sure local storage directory exists
      path = settings.carrier[:local_path]
      if not Dir.exists? path
        Dir.mkdir path
      end
    end

    # moves the temporary image 
    def store!(temp)
      image = gen_filename(temp)

      # move temporary files:
      puts "moving image file: #{temp.image} -> #{image.local.to_s}"
      FileUtils.mv(temp.image, image.local.to_s)
      File.chmod(0664, image.local.to_s)

      temp.thumbnails.each_pair do |width, thumb|
        path = image.thumbnail(width.to_i).local.to_s
        puts "moving image file: #{thumb} -> #{path}"
        FileUtils.mv(thumb, path)
        File.chmod(0664, path)
      end

      image.to_s # returns image path 'YYYYMM/zg.foo.png'
    end

    def retrieve!(image_path)
      Image.new(image_path)
    end

    def destroy!(image_path)
      image = Image.new image_path

      File.unlink image.local.to_s if File.exists? image.local.to_s
      [200, 480].each do |width|
        File.unlink image.thumbnail(width).local.to_s if File.exists? image.thumbnail(width).local.to_s
      end
    end

    private

    def gen_filename(temp)
      def base64_filename(image, hash, suffix, prefix='zg.')
        (1..6).each do |k|
          partial = hash[0...(k*3)]
          partial = partial.ljust(k*3) if k == 6 # "impossible"
          encoded = Base64::urlsafe_encode64(partial).downcase
          test_image = Image.new([image.to_s, '/', prefix, encoded, suffix].join)
          return test_image if not test_image.exists?
        end
        return nil
      end

      # begin with <YYYY><MM>
      image = Image.new temp.created_at.strftime('%Y%m')
      # create directory for year/month
      Dir.mkdir image.local.to_s if not Dir.exists? image.local.to_s

      base64_filename(image, temp.md5obj.digest, '.'+temp.extension)
    end
  end

end

