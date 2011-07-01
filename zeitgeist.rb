require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'
require 'dm-migrations'
require 'dm-types'
require 'carrierwave'
require 'carrierwave/datamapper'
require 'mini_magick'
require 'securerandom'

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

  # z0mg so much fail
  def filename
    #"#{ze_time}_#{model.image.file.filename}"
    "#{ze_time}.#{model.image.file.extension}" if original_filename
  end

  version :thumbnail do
    process :resize_to_limit => [300, 300]
    # lolwut
    #def full_filename(for_file = model.image.file)
      #"#{ze_time}_thumbnail_#{original_filename}" if original_filename
    #end
  end
end

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :source,     String
  property :type,       Enum[:image, :video, :audio, :link], :default => :image
  property :name,       String
  property :image,      String, :auto_validation => false

  mount_uploader :image, ImageUploader

  #property :size,       Integer
  #property :checksum,   String
  #property :flagged,    Boolean
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

post '/' do
  @item = Item.new(:image => params['image_upload'],
                   :remote_image_url => params['remote_url'])

  if @item.save
    redirect '/'
  end
end

get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end
