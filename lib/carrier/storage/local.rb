
module Sinatra::Carrier
  
  module Storage

    class LocalStore < AbstractStore
      def initialize
        assetpath = './public/' + settings.assetpath
        if not Dir.exists? assetpath
          Dir.mkdir assetpath
        end
      end

      def store!(temp)
        image = temp.filename
        thumbnail = temp.filename('_200')

        # move image and thumbnail to final local directory
        image_local = localpath image
        thumbnail_local = localpath thumbnail
        puts "move temporary image to local storage: #{image_local}"
        puts "move temporary thumbnail to local storage: #{thumbnail_local}"
        if not File.exists? image_local
          FileUtils.mv(temp.image, image_local)
        end
        if not File.exists? thumbnail_local
          FileUtils.mv(temp.thumbnail, thumbnail_local)
        end

        super + [image, thumbnail].join('|')
      end

      def retrieve!(identifier)
        super

        image, thumbnail = identifier.split('|')

        Image.new(webpath(image), webpath(thumbnail))
      end

      def destroy!(identifier)
        super

        image, thumbnail = identifier.split('|')

        File.unlink localpath(image) if File.exists? localpath(image)
        File.unlink localpath(thumbnail) if File.exists? localpath(thumbnail)
      end

      private

      def localpath(storepath)
        File.expand_path('./'+storepath, './public/'+settings.assetpath)
      end

      def webpath(storepath)
        File.expand_path('./'+storepath, '/'+settings.assetpath)
      end
    end

  end # Storage

end

