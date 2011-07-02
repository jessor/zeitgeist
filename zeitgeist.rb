require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'
require 'rack-flash'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'
require 'dm-migrations'
require 'dm-types'
require 'carrierwave'
require 'carrierwave/datamapper'
require 'mini_magick'
require 'filemagic'
require 'digest/md5'

#
# Config
#
configure do
  set :pagetitle => '#woot zeitgeist'
  set :assetpath => './asset'
  set :haml, {:format => :html5}
end

#
# Models
#
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/zeitgeist.db")

class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  storage :file

  def store_dir
    "#{settings.assetpath}/"
  end

  def extensions_white_list
    %w(jpg jpeg gif png)
  end

  def ze_time
    Time.now.strftime("%y%m%d%H%M%S")
  end

  # z0mg so much fail... also: race conditions
  #def filename
    #"#{ze_time}.#{model.image.file.extension}" if original_filename
  #end

  version :thumbnail do
    process :resize_to_fill => [200, 200] # http://rubydoc.info/github/jnicklas/carrierwave/master/CarrierWave/MiniMagick/ClassMethods
    # lolwut
    # def full_filename(for_file = model.image.file)
    #   "#{ze_time}_thumbnail_#{original_filename}" if original_filename
    # end
  end
end

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :type,       Enum[:image, :video, :audio, :link], :default => :image
  property :image,      String, :auto_validation => false
  property :source,     String
  property :name,       String
  property :mimetype,   String
  property :size,       Integer
  property :checksum,   String
  property :dimensions, String

  mount_uploader :image, ImageUploader
  has n, :tags, :through => Resource
end

class Tag
  include DataMapper::Resource

  property :id,         Serial
  property :tagname,    String, :unique => true

  has n, :items, :through => Resource
end

DataMapper.finalize
DataMapper.auto_upgrade!

#
# Routes
# 
get '/' do
  @items = Item.all
  haml :index
end

post '/new' do

  # we got ourselves an upload, sir
  if params['remote_url'].empty?
    tempfile = params['image_upload'][:tempfile].path # => /tmp/RackMultipart20110702-17970-zhr4d9
    mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(tempfile) # => image/png; charset=binary
    checksum = Digest::MD5.file(tempfile).to_s # => 649d6151fbe0ffacbed9e627c01b29ad
    filesize = File.size(tempfile)
    filename = params['image_upload'][:filename]
    if mimetype.split("/").first.eql? "image"
      imgobj = MiniMagick::Image.open(tempfile)
      dimensions = "#{imgobj["dimensions"].first}x#{imgobj["dimensions"].last}"
    end
  end

  @item = Item.new(:image => params['image_upload'],
                   :mimetype => mimetype,
                   :checksum => checksum,
                   :dimensions => dimensions,
                   :size => filesize,
                   :name => filename,
                   :remote_image_url => params['remote_url']
                  )

  if @item.save
    redirect '/'
  else
    rais "#{@item.errors}"
  end
end

post '/edit/:id' do

  item = Item.get(params[:id])

  tag = Tag.first_or_create(:tagname => params[:tag])
  item.tags << tag

  if item.save and tag.save
    redirect '/'
  else
    raise "#{item.errors} ===== #{tag.errors.inspect}"
  end

end

get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end
