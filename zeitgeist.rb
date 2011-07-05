require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'
require 'rack-flash'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'
require 'dm-migrations'
require 'carrierwave'
require 'carrierwave/datamapper'
require 'mini_magick'
require 'filemagic'
require 'digest/md5'
require 'json'

#
# Config
#
configure do
  set :pagetitle => '#woot zeitgeist'
  set :pagedesc => 'media collected by irc nerds'
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

  version :thumbnail do
    # http://rubydoc.info/github/jnicklas/carrierwave/master/CarrierWave/MiniMagick/ClassMethods
    process :resize_to_fill => [200, 200]
  end
end

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :type,       String
  property :image,      String, :auto_validation => false
  property :source,     Text
  property :name,       String
  property :mimetype,   String
  property :size,       Integer
  property :checksum,   String
  property :dimensions, String
  property :created_at, DateTime

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
# Helpers
# 

helpers do
  def is_image?(mimetype)
    return true if mimetype.split("/").first.eql? "image"
  end

  def get_dimensions(tempfile)
    imgobj = MiniMagick::Image.open(tempfile)
    return "#{imgobj["dimensions"].first}x#{imgobj["dimensions"].last}"
  end

  def check_url(url)
    case
    when url.match(/^http[s]?:\/\/soundcloud\.com\/[\S]+\/[\S]+\//)
      return 'audio', 'soundcloud'
    when url.match(/^http[s]?:\/\/www\.youtube\.com\/watch\?v=[a-zA-Z0-9]+/)
      return 'video', 'youtube'
    end
  end

  def is_ajax_request?
    if respond_to? :content_type
      if request.xhr?
        true
      else
        false
      end
    else
      false
    end
  end

  def fileprefix
    "#{Time.now.strftime("%y%m%d%H%M%S")}_zeitgeist"
  end

end

#
# Routes
# 

get '/' do
  @items = Item.all.reverse
  haml :index
end

get '/filter/by/type/:type' do
  @items = Item.all(:type => params[:type]).reverse
  haml :index
end

get '/filter/by/tag/:tag' do
  @items = Item.all(Item.tags.tagname => params[:tag]).reverse
  haml :index
end

# we got ourselves an upload, sir
post '/new' do

  # if it's an upload
  if params['remote_url'].empty?
    # prevent file collisions the hacky way
    unless params['image_upload'][:filename].empty?
      params['image_upload'][:filename] = "#{fileprefix}_#{params['image_upload'][:filename]}"
    end
    tempfile = params['image_upload'][:tempfile].path # => /tmp/RackMultipart20110702-17970-zhr4d9
    mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(tempfile) # => image/png; charset=binary
    checksum = Digest::MD5.file(tempfile).to_s # => 649d6151fbe0ffacbed9e627c01b29ad
    filesize = File.size(tempfile)
    filename = params['image_upload'][:filename]
    dimensions = get_dimensions(tempfile) if is_image?(mimetype)
    type = 'image'
  # if it's a url
  else
    # pass url to carrierwave unless we recognize it
    if thisurl = check_url(params['remote_url'])
      type, site = thisurl
    else
      imageurl = params['remote_url']
      type = 'image'
    end
  end

  # let's put it together
  begin
    @item = Item.new(:image => params['image_upload'],
                     :source => params['remote_url'],
                     :mimetype => mimetype,
                     :checksum => checksum,
                     :dimensions => dimensions,
                     :size => filesize,
                     :name => filename,
                     :type => type,
                     :remote_image_url => imageurl
                    )
  # if there's a problem with the new object
  rescue Exception => ex
    @downloaderror = Downloaderror.new(:source => params['remote_url'],
                       :code => ex.message 
                      )
    @downloaderror.save
    flash[:error] = "#{ex.message}"
    redirect '/'
  # else put it in the database
  else

    begin
      @item.save
    # if there's a problem while saving
    rescue Exception => ex
      flash[:error] = "#{ex.message}"
    else
      flash[:notice] = "New item added successfully."
    end

    redirect '/'
  end
end

# add tags to items
post '/edit/:id' do
  # get selected item object
  @item = Item.get(params[:id])

  # strip leading/preceding whitespace and html tags
  newtags = params[:tag].gsub(/(^[\s]+|<\/?[^>]*>|[\s]+$)/, "")

  newtags.split(',').each do |newtag|
    newtag.strip!
    # get or create tag object
    tag = Tag.first_or_create(:tagname => newtag)
    # (try to) save tag
    if not tag.save
      flash[:error] = "#{tag.errors}"
      break
    end
    # create association
    @item.tags << tag
  end

  # save item with new tags
  if not @item.save
    flash[:error] = "#{@item.errors}"
  end

  if is_ajax_request?
    haml :plain, :layout => false
  else
    redirect '/'
  end
end

get '/feed' do
  @items = Item.all.reverse
  builder :itemfeed
end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end
