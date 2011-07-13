
module Sinatra::Carrier

  # the retrieve method of each storage should return an Image object:
  # includes URIs that can be used in views
  class Image
    attr_reader :thumbnail

    def initialize(image, thumbnail)
      @image = image
      @thumbnail = thumbnail
    end

    def to_s
      @image
    end
  end

  module Storage

    def self.create(store_name)
      self.const_get("#{store_name.capitalize}Store").new
    end

    # the existing files store an identifier in the database that
    # can be resolved to an absolute URI by the store that was 
    # accountable for storing the file
    def self.create_by_identifier(identifier)
      # the store that was responsible for creating the file
      if identifier.match /(<store:(.*)>)/
        identifier.slice $1
        self::create $2
      else
        raise 'identifier without storename'
      end
    end

    class AbstractStore
      # should not be called directly!
      def initialize
        raise NotImplementedError
      end

      def store!(local_temp)
        if self.class.name.match /:([A-Z]\w+)Store/
          "<store:#{$1.downcase}>"
        else
          raise 'invalid store name: ' + self.class.name
        end
      end

      def retrieve!(identifier)
        if identifier.match /(<store:[^>]+>)/
          identifier.slice! $1
        end
      end

      def destroy!(identifier)
        if identifier.match /(<store:[^>]+>)/
          identifier.slice! $1
        end
      end
    end

  end # Storage

end

# TODO: dynamic loading?
require File.dirname(File.expand_path(__FILE__)) + '/storage/local.rb'

