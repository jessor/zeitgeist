
module Sinatra::Carrier
  
  module Storage

    class LocalStore < Store
      @@options = nil
      def initialize
        @@options = settings.carrier[:local] if not @@options
        if not Dir.exists? @@options[:path]
          Dir.mkdir @@options[:path]
        end
      end

      def store!(temp)
        image = gen_filename(temp)
        thumbnail = gen_filename(temp, '_200')

        # the full local path: (including the path setting)
        image_local = localpath image
        thumbnail_local = localpath thumbnail

        # move temporary files into position, another storage
        # type might upload it here to another server or alike
        FileUtils.mv(temp.image, image_local)
        FileUtils.mv(temp.thumbnail, thumbnail_local)

        # fix permissions
        File.chmod(0664, image_local)
        File.chmod(0664, thumbnail_local)

        # this returns the string to store in the database,
        # the base class returns the identifier with the name
        # of this storage(<store:local>) (@see retrieve!)
        super + [image, thumbnail].join('|')
      end

      def retrieve!(identifier)
        super

        image, thumbnail = identifier.split('|')

        Image.new(webpath(image), webpath(thumbnail))
      end

      def retrieve_local!(identifier)
        if identifier.match /(<store:[^>]+>)/
          identifier.slice! $1
        end

        image, thumbnail = identifier.split('|')

        Image.new(localpath(image), localpath(thumbnail))
      end

      def destroy!(identifier)
        super

        image, thumbnail = identifier.split('|')

        File.unlink localpath(image) if File.exists? localpath(image)
        File.unlink localpath(thumbnail) if File.exists? localpath(thumbnail)
      end

      private

      def localpath(storepath)
        File.expand_path('./' + storepath, @@options[:path])
      end

      def webpath(storepath)
        @@options[:url_base] + storepath
      end

      def gen_filename(temp, suffix='')
        def base64_filename(path, hash, suffix, prefix='zg.')
          path += '/' if path[-1] != '/'
          (1..6).each do |k|
            partial = hash[0...(k*3)]
            partial = partial.ljust(k*3) if k == 6 # "impossible"
            encoded = Base64::urlsafe_encode64(partial).downcase
            filename = prefix + encoded + suffix
            return filename if not File.exists?(File.expand_path(filename, path))
          end
          return nil
        end

        date_dir = temp.created_at.strftime('%Y%m')
        full_path = localpath date_dir
        # create directory for year/month if not existing:
        Dir.mkdir full_path if not Dir.exists? full_path

        filename = base64_filename(full_path, temp.md5obj.digest, suffix+'.'+temp.extension)

        "/#{date_dir}/#{filename}"
      end
    end

  end # Storage

end

