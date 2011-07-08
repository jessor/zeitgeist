%w(rubygems sinatra haml sass rack-flash dm-core dm-validations dm-timestamps dm-migrations dm-serializer carrierwave carrierwave/datamapper mini_magick filemagic digest/md5 json uri yaml oembed dm-pager builder).each do |gem|
  require gem
end
require_relative 'remote.rb'

#
# Config
#
configure do
  set :haml, {:format => :html5}
  set :raise_errors, false
  set :show_exceptions, false
  use Rack::Flash
  enable :sessions
  set :allowed_mime, ['image/png', 'image/jpeg', 'image/gif']

  yaml = YAML.load_file('config.yaml')
  yaml.each_pair do |key, value|
    set(key.to_sym, value)
  end
end

#
# Models
#
if settings.respond_to? 'datamapper_logger'
  DataMapper::Logger.new(STDOUT, settings.datamapper_logger)
end
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

# initialize oembed
# later detect embed provider by url 
# (if not overwritten by url)
OEmbed::Providers.register_all

#
# Helpers
# 

helpers do

  include Rack::Utils
  alias_method :h, :escape_html

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
# General Filters
# 
before do
  if request.host =~ /^www\./
    redirect "http://#{request.host.gsub('www.', '')}:#{request.port}", 301
  end
end

#
# Routes
# 

get '/' do
  @autoload = h params['autoload'] if params['autoload']
  @items = Item.page(params['page'], 
                     :per_page => settings.items_per_page,
                     :order => [:created_at.desc])
  @pagination = @items.pager.to_html('/', :size => 5)
  haml :index
end

get '/filter/by/type/:type' do
  @items = Item.all(:type => params[:type], :order => [:created_at.desc])
  haml :index
end

get '/filter/by/tag/:tag' do
  @items = Item.all(Item.tags.tagname => params[:tag], :order => [:created_at.desc])
  haml :index
end

get '/about' do
  if is_ajax_request?
    haml :about, :layout => false
  else
    haml :about
  end
end

post '/embed' do
  remoteplugin = Sinatra::ZeitgeistRemote::Plugins::plugin_by_url(params['url'])
  remoteplugin.oembed.html
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

get '/search' do
  if is_ajax_request?
    haml :search, :layout => false
  else
    haml :search
  end
end

get '/new' do
  if is_ajax_request?
    haml :new, :layout => false
  else
    haml :new
  end
end

get '/item/:id' do
  @item = Item.get(params[:id])
  if not @item
    error = "no item found with id #{params[:id]}"
  end

  if is_ajax_request?
    content_type :json
    if error
      {:error => error}.to_json
    else
      {:item => @item, :tags => @item.tags}.to_json
    end
  else
    if error
      flash[:error] = error
      redirect '/'
    else
      redirect @item.image
    end
  end
end

# we got ourselves an upload, sir
# with params for image_upload or remote_url
post '/new' do
  notice = error = nil
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
    begin
      downloader = Sinatra::ZeitgeistRemote::RemoteDownloader.new(source)
    rescue Sinatra::ZeitgeistRemote::RemoteException => e
      error = e.message
      puts "remote exception: #{e.message}"
      puts e.traceback.join "\n"
    else
      type = downloader.type
      if downloader.tempfile
        upload = {
          :tempfile => File.open(downloader.tempfile),
          :filename => "#{fileprefix}_#{downloader.filename}"
        }
        filesize = downloader.filesize
        filename = downloader.filename
      end
    end

  else
    error = 'You need to specifiy either a file or remote url for uploading!'
  end

  puts upload.inspect

  # check upload file and generate meta infos
  if not error and upload
    begin
      mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(upload[:tempfile].path)
      mimetype = mimetype.slice 0...mimetype.index(';')
      if settings.allowed_mime.include? mimetype
        type = 'image' if not type
        upload[:content_type] = mimetype

        # more meta information (only for image types!)
        checksum = Digest::MD5.file(upload[:tempfile].path).to_s
        filesize = File.size(upload[:tempfile].path) if not filesize
        img = MiniMagick::Image.open(upload[:tempfile].path)
        dimensions = img["dimensions"].join 'x' 

        # if the file extension does not match 
        # with the detected mimetype change it
        ext = File.extname(upload[:filename])
        mime_ext = '.' + mimetype.slice(mimetype.index('/')+1, mimetype.length)
        if ext.empty? or ext != mime_ext
          # strip existing extension:
          upload[:filename].slice!(ext)

          # append correct extension based on mimetype
          upload[:filename] += mime_ext

        end
      else
        error = "Image file with invalid mimetype: #{mimetype}!"
      end
    rescue Exception => e
      error = "Unable to determine upload meta information: #{e.message}"
    end
  end

  if not error
    puts "mime:#{mimetype} type:#{type} checksum:#{checksum} filesize:#{filesize} dimensions:#{dimensions}"

    # for non image types hash the original url instead of
    # (preview) image or nil
    if type != 'image'
      checksum = Digest::MD5.hexdigest(source)
    end

    # check for duplicate images before inserting
    if checksum and (item = Item.first(:checksum => checksum))
      error = "Duplicate image found based on checksum, id: #{item.id}"
    else
      # store in database, let carrierwave take care of the upload
      @item = Item.new(:type => type, :image => upload, :source => source,
                  :name => filename[0...49], :size => filesize, :mimetype => mimetype,
                  :checksum => checksum, :dimensions => dimensions)
      if not @item.save
        error = "#{@item.errors.full_messages.inspect}"
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
  if type and not error
    notice = "New item added successfully."
  end

  if is_ajax_request?
    content_type :json
    if @item
      item = @item
      tags = @item.tags
    else
      item = nil
      tags = nil
    end
    {
      :error => error, 
      :notice => notice,
      :item => item,
      :tags => tags
    }.to_json
  else
    flash[:error] = error
    flash[:notice] = notice
    redirect '/'
  end
end

# adds or removes tags from an item
post '/edit/:id' do
  id = params[:id]
  add_tags = (params[:add_tags] || '').split(',').map { |tag| tag.strip!; tag.gsub(/<\/?[^>]*>/,'') }
  del_tags = (params[:del_tags] || '').split(',').map { |tag| tag.strip!; tag.gsub(/<\/?[^>]*>/,'') }

  added_tags = []
  deleted_tags = []

  # get the item to edit
  @item = Item.get(id)
  if not @item
    error = "item with id #{id} not found!"
  else
    add_tags.each do |tag|
      puts add_tags.inspect
      newtag = Tag.first_or_create(:tagname => tag)
      puts newtag.inspect
      # (try to) save tag
      if not newtag or not newtag.save
        error = "#{newtag.errors}"
        break
      end
      # create association
      @item.tags << newtag
      added_tags << newtag
    end

    # only allow adding tags with api key:
    if params[:api_secret] and params[:api_secret] == settings.api_secret 
      del_tags.each do |tag|
        @item.tags.each do |old_tag|
          if old_tag.tagname == tag 
            @item.tags.delete(old_tag) 
            deleted_tags << old_tag
          end
        end
      end
    end

    if not @item.save
      error = @item.errors
    end
  end

  if is_ajax_request?
    content_type :json
    if error
      {:error => error}.to_json
    else
      {:added_tags => added_tags, :deleted_tags => deleted_tags}.to_json
    end
  else
    flash[:error] = error 
    redirect '/'
  end
end

get '/feed' do
  @items = Item.all(:limit => 10, :order => [:created_at.desc])
  builder :itemfeed 
end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end
