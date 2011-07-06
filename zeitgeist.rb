require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'
require 'rack-flash'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'
require 'dm-migrations'
require 'dm-serializer'
require 'carrierwave'
require 'carrierwave/datamapper'
require 'mini_magick'
require 'filemagic'
require 'digest/md5'
require 'json'
require 'uri'
require 'yaml'

require './remote.rb'

#
# Config
#
configure do
  yaml = YAML.load_file('config.yaml')
  yaml.each_pair do |key, value|
    set(key.to_sym, value)
  end

  set :haml, {:format => :html5}
  set :raise_errors, false
  set :show_exceptions, false
  use Rack::Flash
  enable :sessions
  set :allowed_mime, ['image/png', 'image/jpeg', 'image/gif']
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
  property :type,       String # image, video, audio
  property :image,      String, :auto_validation => false
  property :source,     Text   # set to original (remote) url
  property :name,       String # original filename
  property :created_at, DateTime

  # image meta information
  property :size,       Integer
  property :mimetype,   String
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
# Helpers
# 

helpers do

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

post '/search' do
  @items = Tag.all(:tagname.like => "%#{params['searchquery']}%")
  if is_ajax_request?
    content_type :json
    @items.to_json
  else
    redirect "/filter/by/tag/#{params['searchquery']}"
  end
end

# we got ourselves an upload, sir
# with params for image_upload or remote_url
post '/new' do
  type = upload = source = filename = filesize = mimetype = checksum = dimensions = nil
  if params[:image_upload]
    filename = params['image_upload'][:filename]
    upload = {
      :tempfile => params[:image_upload][:tempfile],
      :filename => "#{fileprefix}_#{filename}"
    }

  # remote upload
  elsif params[:remote_url] and params[:remote_url] =~ /^http[s]?:\/\//
    source = params[:remote_url]
    if source =~ /^http[s]?:\/\/soundcloud\.com\/[\S]+\/[\S]+\//
      type = 'audio'
    elsif source =~ /^http[s]?:\/\/www\.youtube\.com\/watch\?v=[a-zA-Z0-9]+/
      type = 'video'
    else
      begin
        downloader = Sinatra::ZeitgeistRemote::ImageDownloader.new(source)
      rescue Sinatra::ZeitgeistRemote::RemoteException => e
        error = e.message
      else
        filename = File.basename(URI.parse(downloader.url).path)
        filename.gsub!(/[^a-zA-Z0-9_\-\.]/, '')
        upload = {
          :tempfile => File.open(downloader.tempfile),
          :filename => "#{fileprefix}_#{filename}"
        }
        filesize = downloader.filesize
      end
    end

  else
    error = 'You need to specifiy either a file or remote url for uploading!'
  end

  puts upload.inspect

  # check upload file and generate meta infos
  if not error and upload
    begin
      mime = FileMagic.new(FileMagic::MAGIC_MIME).file(upload[:tempfile].path)
      mime = mime.slice 0...mime.index(';')
      if settings.allowed_mime.include? mime
        type = 'image'

        # more meta information (only for image types!)
        checksum = Digest::MD5.file(upload[:tempfile].path).to_s
        filesize = File.size(upload[:tempfile].path) if not filesize
        img = MiniMagick::Image.open(upload[:tempfile].path)
        dimensions = img["dimensions"].join 'x' 
      else
        error = "Image file with invalid mimetype: #{mime}!"
      end
    rescue Exception => e
      error = "Unable to determine upload meta information: #{e.message}"
    end
  end

  if type and not error
    puts "mime:#{mime} type:#{type} checksum:#{checksum} filesize:#{filesize} dimensions:#{dimensions}"

    # check for duplicate images before inserting
    if checksum and (item = Item.first(:checksum => checksum))
      error = "Duplicate image found based on checksum, id: #{item.id}"
    else
      # store in database, let carrierwave take care of the upload
      @item = Item.new(:type => type, :image => upload, :source => source,
                  :name => filename, :size => filesize, :mimetype => mimetype,
                  :checksum => checksum, :dimensions => dimensions)
      if not @item.save
        error = "#{@item.errors}"
      else
        # save new tags if present
        if params[:tags]
          params[:tags].split(',').each do |newtag|
            newtag.strip!
            tag = Tag.first_or_create(:tagname => newtag)
            if not tag.save
              error = "#{tag.errors}"
              break
            end
            @item.tags << tag
          end
          @item.save # save the new associations
        end
      end
    end
  end

  # upload error:
  if error or not type
    flash[:error] = error
  else
    flash[:notice] = "New item added successfully."
  end

  if is_ajax_request?
    if @item
      item = @item.to_json
    else
      item = nil
    end
    {
      :error => flash[:error], 
      :notice => flash[:notice],
      :item => item
    }.to_json
  else
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
