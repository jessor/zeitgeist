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

  def classify_url(url)
    case
    when url.match(/^http[s]?:\/\/soundcloud\.com\/[\S]+\/[\S]+/)
      return 'audio', 'soundcloud'
    when url.match(/^http[s]?:\/\/www\.youtube\.com\/watch\?v=_?+[a-zA-Z0-9]+/)
      return 'video', 'youtube'
    when url.match(/^http[s]?:\/\/vimeo\.com\/\d+/)
      return 'video', 'vimeo'
    end
  end

  def custom_provider(provider)
    case
    when provider =~ /soundcloud/i
      return OEmbed::Provider.new('http://soundcloud.com/oembed')
    end
  end

end

#
# Routes
# 

get '/' do
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

post '/embed' do
  provider = params['provider'].capitalize
  if OEmbed::Providers::const_defined? provider
    provider = OEmbed::Providers::const_get(provider)
  else
    provider = custom_provider(params['provider'])
  end
  @resource = provider.get(params['url'])
  if is_ajax_request?
    haml :embed, :layout => false
  end
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
    if this_source = classify_url(source)
      type, filename = this_source
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
      mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(upload[:tempfile].path)
      mimetype = mimetype.slice 0...mimetype.index(';')
      if settings.allowed_mime.include? mimetype
        type = 'image'
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

  if type and not error
    puts "mime:#{mimetype} type:#{type} checksum:#{checksum} filesize:#{filesize} dimensions:#{dimensions}"

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

# add tags to items
post '/edit/:id' do
  # get selected item object
  @item = Item.get(params[:id])
  if @item
    # strip leading/preceding whitespace and html tags
    newtags = params[:tag].gsub(/(^[\s]+|<\/?[^>]*>|[\s]+$)/, "")

    newtaglist = []
    newtags.split(',').each do |newtag|
      newtag.strip!
      # get or create tag object
      tag = Tag.first_or_create(:tagname => newtag)
      # (try to) save tag
      if not tag.save
        error = "#{tag.errors}"
        break
      end
      # create association
      @item.tags << tag
      newtaglist << tag
    end

    # save item with new tags
    if not @item.save
      error = "#{@item.errors}" 
    end
  else
    error = "no item found with id #{params[:id]}"
  end

  if is_ajax_request?
    content_type :json
    if error
      {:error => error}.to_json
    else
      {:tags => newtaglist}.to_json
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
