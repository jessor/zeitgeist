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
  set :raise_errors, false
  set :show_exceptions, false
  use Rack::Flash
  enable :sessions
  # http://stackoverflow.com/questions/5631862/problem-with-sinatra-and-session-variables-which-are-not-being-set/5677589#5677589
  set :session_secret, "fixing this for shotgun"
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

  version :thumbnail do
    process :resize_to_fill => [200, 200] # http://rubydoc.info/github/jnicklas/carrierwave/master/CarrierWave/MiniMagick/ClassMethods
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

class Downloaderror
  include DataMapper::Resource

  property :id,         Serial
  property :source,     Text
  property :code,       String
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

# we got ourselves an upload, sir
post '/new' do
  # if it's an upload
  if params['remote_url'].empty?
    tempfile = params['image_upload'][:tempfile].path # => /tmp/RackMultipart20110702-17970-zhr4d9
    mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(tempfile) # => image/png; charset=binary
    checksum = Digest::MD5.file(tempfile).to_s # => 649d6151fbe0ffacbed9e627c01b29ad
    filesize = File.size(tempfile)
    filename = params['image_upload'][:filename]
    # if upload is an image 
    if mimetype.split("/").first.eql? "image"
      imgobj = MiniMagick::Image.open(tempfile)
      dimensions = "#{imgobj["dimensions"].first}x#{imgobj["dimensions"].last}"
    end
  end

  # let's put it together
  begin
    @item = Item.new(:image => params['image_upload'],
                     :mimetype => mimetype,
                     :checksum => checksum,
                     :dimensions => dimensions,
                     :size => filesize,
                     :name => filename,
                     :remote_image_url => params['remote_url']
                    )
  # if there's a problem with the new object
  rescue Exception => ex
    @downloaderror = Downloaderror.new(:source => params['remote_url'],
                       :code => ex.message 
                      )
    @downloaderror.save
    flash[:error] = "Error: #{ex.message}"
    redirect '/'
  # else put it in the database
  else
    begin
      @item.save
    # if there's a problem while saving
    rescue
      flash[:error] = "Error: #{@item.error}"
    else
      flash[:notice] = "New item added successfully."
    end
    redirect '/'
  end
end

# add tags to items
post '/edit/:id' do
  # get selected item object
  item = Item.get(params[:id])

  # get or create tag object
  tag = Tag.first_or_create(:tagname => params[:tag])
  # create association
  item.tags << tag

  if item.save and tag.save
    redirect '/'
  else
    flash[:error] = "Error: #{@item.errors}"
  end
end

#error do
  #'meh...' + env['sinatra.error'].message
  #haml :'foo'
#end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end
