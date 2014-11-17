require 'rubygems'
require 'bundler/setup'

Bundler.require(:default, :qrencoder, :phashion)

# ruby core requirements
require 'base64'
require 'digest/md5'
require 'json'
require 'uri'
require 'yaml'
require 'drb'

# remote url download library
require './lib/remote/remote.rb'

# upload, validate, process tempfile
require './lib/carrier/carrier.rb'

# used to symbolize the yaml config file
module HashExtensions
  def symbolize_keys
    inject({}) do |acc, (k,v)|
      key = String === k ? k.to_sym : k
    value = Hash === v ? v.symbolize_keys : v
    acc[key] = value
    acc
    end
  end
end
Hash.send(:include, HashExtensions)

#
# Error Handling
#

class Exception
  # custom to_json method that defines the default for the Zeitgeist API
  def api_to_json(child_obj={}, d=nil)
    {
      :type => self.class.to_s,
      :message => self.message
    }.merge(child_obj).to_json
  end

  def to_json(*args)
    api_to_json
  end
end

class DuplicateError < StandardError
  attr_reader :id
  def initialize(id)
    @id = id
    super "Duplicate item found! ID: #{id}"
  end

  def to_json(*args)
    api_to_json(:id => @id)
  end
end

class CreateItemError < StandardError
  attr_reader :error
  attr_reader :items
  def initialize(error, items, tags)
    @error = error
    @items = items
    super 'Error creating item: %s' % error.to_s
  end

  def to_json
    api_to_json(
      :error => @error,
      :items => @items
    )
  end
end

class RemoteError < StandardError
  attr_reader :error
  attr_reader :url
  def initialize(error, url)
    @error = error
    @url = url
  end

  def to_json(*args)
    api_to_json({
      :error => @error,
      :url => @url
    }, args)
  end
end

#
# Config
#
configure do
  # configure by yaml file:
  yaml = YAML.load_file('config.yaml').symbolize_keys

  # apply environment specific options:
  yaml = yaml.merge yaml[settings.environment.to_sym]
  yaml.delete :production
  yaml.delete :development

  yaml.each_pair do |key, value|
    set(key, value)
  end

  enable :sessions
  enable :logging
  use Rack::Flash

  set :sessions, :expire_after => 315360000
  set :haml, {:format => :html5}
  set :protection, :except => :frame_options
  set :allowed_mime, ['image/png', 'image/jpeg', 'image/gif', 'video/webm']
  set :sinatra_authentication_view_path, 'views/auth_'
  # NOTE: _must_ be disabled otherwise our custom error handler does not work correctly 
  disable :show_exceptions
  disable :dump_errors
  disable :raise_errors 
end

#
# Models
#
if settings.respond_to? 'datamapper_logger'
  puts "Setup DataMapper logging: #{settings.datamapper_logger}"
  DataMapper::Logger.new(STDOUT, settings.datamapper_logger)
end
if settings.database[:adapter] == 'mysql'
  Bundler.require(:mysql)
elsif settings.database[:adapter] == 'sqlite'
  Bundler.require(:sqlite)
end
DataMapper.setup(:default, settings.database)

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :type,       String, :default => 'image' # image, video, audio
  property :image,      String, :auto_validation => false
  property :source,     Text   # set to original (remote) url
  property :title,      Text
  property :created_at, DateTime
  # currently this only 'caches' if this item has the nsfw tag or not
  # otherwise its stupidly difficult with dm to query non-nsfw tagged items
  property :nsfw,       Boolean, :default => false

  # item submitter
  belongs_to :dm_user, :required => false

  # phash fingerprint
  property :fingerprint, Integer

  # image meta information
  property :size,       Integer
  property :mimetype,   String
  property :checksum,   String, :unique => true
  property :dimensions, String

  # taggings
  has n, :tags, :through => Resource

  # hooks for processing either the upload or remote url
  # NOTE: raise a RuntimeError if something went wrong!
  before :create do
    tempfile = @image
    self.title = nil if self.title and self.title.empty?
    self.type = 'image' if not self.type

    if not tempfile and @source # remote upload!
      link = self.type == 'link'
      @plugin = Sinatra::Remote::Plugins::Loader::create(@source, link ? 'Generic' : nil)
      raise 'invalid url!' if not @plugin

      if @plugin.url and not link
        puts "Download remote content from url: #{@plugin.url}"
        downloader = Sinatra::Remote::Downloader.new(@plugin.url)
        begin
          downloader.download!
        rescue Exception => e
          puts $!
          puts $@.join("\n")
          raise RemoteError.new(e, @source)
        else
          tempfile = downloader.tempfile
          self.size = downloader.filesize
        end
      elsif link
        # take a snapshot of the website
        webshot = File.join(File.dirname(__FILE__), 'extra/webshot.sh')
        io = IO.popen([webshot, @source, settings.agent], 'r+')
        tmp = io.readlines
        puts tmp.join("\n")
        tmp_path = tmp.last
        io.close
        if $? == 0 and tmp_path and File.exists?(tmp_path.chomp!)
          tempfile = tmp_path
          self.size = nil
        else
          raise RemoteError.new('unable to create screenshot (%d)' % $?, @source)
        end
      elsif @plugin.type == 'image'
        # plugins for image hosting providers need to return a media url,
        # and can not just live with their source url alone
        raise "selected plugin (#{@plugin.class.to_s}) doesn't found image"
      end

      self.type = @plugin.type
      if @plugin.title
        if self.title
          self.title = '%s (%s)' % [self.title, @plugin.title]
        else
          self.title = @plugin.title
        end
      end
      if @plugin.tags
        @plugin.tags.each do |tagname|
          if @plugin.only_existing_tags
            # only add existing tags as association:
            tagname.downcase!; tagname.strip!
            tag = Tag.first(:tagname => tagname)
            self.tags << tag if tag
          else
            tagname.downcase!; tagname.strip!
            tag = Tag.first_or_create(:tagname => tagname)
            self.tags << tag if tag
          end
        end
      end
    end

    # here we move the temporary file (from the file upload *or* remote
    #  download) to their final destination (/asset directory), we also
    #  create thumbnails and the image fingerprint.
    if tempfile
      begin
        localtemp = Sinatra::Carrier::LocalTemp.new(tempfile, @created_at)
        localtemp.process! # creates thumbnail, verify image

        self.dimensions = localtemp.dimensions
        self.mimetype = localtemp.mimetype
        self.checksum = localtemp.checksum
        self.size = localtemp.filesize if not @plugin or not self.size
    
        # animated autotagging
        self.tags << Tag.first_or_create(:tagname => 'animated') if localtemp.animated

        # duplication check
        if defined? Phashion and self.type == 'image'
          if self.mimetype == 'video/webm'
            fp = self.generate_fingerprint(localtemp.thumbnails['480'])
          else
            fp = self.generate_fingerprint(tempfile)
          end
          puts "fingerprint generated #{fp}"
          if not self.fingerprint
            self.fingerprint = fp
            if (item = Item.first(:fingerprint => self.fingerprint))
              raise DuplicateError.new(item.id)
            end
            items = Item.similar(self.fingerprint)
            if (items.length >= 1)
              puts "fingerprint (#{self.fingerprint}) distance for #{items[0][0]}: #{items[0][2]}"
              raise DuplicateError.new(items[0][0])
            end
          else
            self.fingerprint = fp # store the fingerprint regardless
          end
        end

        # always check for checksum duplicates (db constraint)
        item = Item.first(:checksum => self.checksum)
        raise DuplicateError.new(item.id) if item

        # store file in configured storage
        self.image = localtemp.store!

        # change/hack for webm, supposed to be video type:
        if self.mimetype == 'video/webm'
          self.type = 'video'
        end
      rescue Exception => e
        raise e
      ensure
        # to make sure tempfiles are deleted in case of an error 
        localtemp.cleanup! 
      end
    end
  end

  after :destroy do
    # get and destory file storage
    store = Sinatra::Carrier::Store.new
    store.destroy! image.to_s
  end

  # returns the Carrier::Image object for this item
  def image
    if not @image_obj
      image_path = attribute_get(:image)
      return if not image_path
      # migration for old style identifiers:
      # <store:local>/200709/zg.uezk.jpeg|/200709/zg.uezk_200.jpeg
      if image_path.match /<[^>]+>([^\|]+)\|/
        image_path = $1
      end
      store = Sinatra::Carrier::Store.new
      @image_obj = store.retrieve! image_path
    end
    @image_obj
  end

  def title
    title = attribute_get(:title)
    if title and not title.valid_encoding?
      puts "Invalid Encoding title(#{title.inspect})!"
      title = title.force_encoding('ISO-8859-1').encode('UTF-8')
      raise 'Broken Encoding!' if not title.valid_encoding?
    end
    return nil if not title or title.empty?
    title.gsub!(/\n/, '')
    title.gsub!(/\r/, '')
    title = title.split.join ' '
    title = CGI.escapeHTML(title)
    if attribute_get(:nsfw)
      return '[NSFW] ' + title
    else
      return title
    end
  end

  # build html title/alternate text
  def html_title
    html_title = "#{self.id}: "
    title = (self.title || self.source)
    return '' if not title
    if self.source =~ /^http/
      html_title += '<a href="%s">%s</a>' % [self.source, title]
    else
      html_title += title
    end
    # dimensions (only relevant for images)
    if self.type == 'image'
      html_title += (' at <a href="/show/dimensions/%s">%s</a>' % 
          [self.dimensions, self.dimensions])
    end
    html_title
  end

  # returns the embed code for this item
  def embed(width=640, height=385)
    return if self.type == 'image'
    if self.mimetype == 'video/webm'
=begin NOTE: unsure about this
      self.dimensions.match /^(\d+)x(\d+)$/
      w = $1
      h = $2
=end
      <<html5
    <video src="#{self.image.web}" width="#{width}" height="#{height}" autoplay controls>
    </video>
html5
    else
      remoteplugin = Sinatra::Remote::Plugins::Loader::create(self.source)
      remoteplugin.embed(width, height) # returns html code for embedding
    end
  end

  def add_tags(tags)
    tags = tags.split(',') if tags.class != Array
    return if tags.empty?
    added_tags = []
    tags.each do |tagname|
      Tag.cleanup! tagname
      tag = Tag.first_or_create(:tagname => tagname)
      if not tag.errors.empty?
        puts "Errors occured: DataMapper first_or_create: " + 
          tag.errors.full_messages.join(',')
        next # just try the next one ;)
      end

      # nsfw item cache property
      self.nsfw = true if tagname == 'nsfw'

      # to keep track of how often this tag is beeing used
      tag.update(:count => tag.count + 1)

      self.tags << tag
      added_tags << tag
    end
    self.save # save the new associations
    return added_tags
  end

  def del_tags(tags)
    tags = tags.split(',') if tags.class != Array
    return if tags.empty?
    puts "Drop tags from item(##{self.id}): #{tags.join('|')}"
    deleted_tags = []
    tags.each do |tag|
      Tag.cleanup! tag
      self.tags.each do |old_tag|
        if old_tag.tagname == tag
          puts "Drop existing tag #{old_tag.tagname}!"
          self.tags.delete(old_tag) 
          deleted_tags << old_tag

          # nsfw item cache property
          self.nsfw = false if tag == 'nsfw'

          # to keep track of how often this tag is beeing used
          old_tag.update(:count => old_tag.count - 1)
        end
      end
    end
    self.save # save the new associations
    return deleted_tags
  end

  def as_json(options={})
    super(options.merge(:methods => [:tags, :username]))
  end

  # uses the pHash perceptual hash library to calculate
  # a 64bit fingerprint of the image
  # returns nil if an error occured or if item is not an image
  def generate_fingerprint(path=nil)
    return nil if type != 'image'
    path = image_local.to_s if not path
    temp_path = nil

    if mimetype.include? 'png'
      # due to a bug in phash the alpha channel of png images
      # need to be removed before generating the fingerprint
      img = ::MiniMagick::Image.open(path)
      if img['%[channels]'] == 'rgba' # image with alpha channel
        # write temporary file without the alpha channel
        img.combine_options do |c|
          c.background 'white' # -background white
          c.flatten # +flatten
          c + '+matte' # +matte
        end
        temp_path = '/tmp/zg_png_%s.png' % checksum
        img.write(temp_path)
        path = temp_path
      end
    end

    # calculate fingerprint...
    img = Phashion::Image.new path
    fingerprint = img.fingerprint

    # remove the temporary file
    File.delete temp_path if temp_path

    return fingerprint
  raise
    puts "error generating fingerprint: #{$!}"
    return nil
  end

  def username
    dm_user.username if dm_user
  end

  # returns the most similar images, with a threshold of <n>
  @@fingerprints = nil
  def self.similar(fingerprint)
    threshold = settings.fingerprint_threshold
    ret = []
    if settings.database[:adapter] == 'mysql'
      sql = 'SELECT id, fingerprint, bit_count(fingerprint ^ %d) AS distance FROM items HAVING distance IS NOT NULL AND distance < %d ORDER BY distance ASC LIMIT 10'
      sql = sql % [fingerprint, threshold]
      repository(:default).adapter.select(sql).each do |res|
        ret << [res.id, res.fingerprint, res.distance]
      end
    else
      if not @@fingerprints
        @@fingerprints = Item.all.aggregate(:id, :fingerprint)
      end
      @@fingerprints.each do |res|
        if res[1]
          distance = Phashion.hamming_distance(res[1], fingerprint)
          if distance <= threshold
            ret << res + [distance]
          end
        end
      end
      ret.sort! do |a, b|
        b[2] <=> a[2]
      end
    end
    return ret
  end
end

class Tag
  include DataMapper::Resource

  property :id,         Serial
  property :tagname,    String, :unique => true

  # count taggings of items with this tag
  property :count,      Integer, :default => 0

  has n, :items, :through => Resource

  def tagname=(tagname)
    if not tagname.valid_encoding?
      puts "Invalid Encoding tagname(#{tagname.inspect})!"
      tagname = tagname.force_encoding('ISO-8859-1').encode('UTF-8')
      raise 'Broken Encoding!' if not tagname.valid_encoding?
    end
    self.class::cleanup! tagname
    super
  end

  def tagname
    tagname = super
    if not tagname.valid_encoding?
      puts "Invalid Encoding tagname(#{tagname.inspect})"
      tagname = tagname.force_encoding('ISO-8859-1').encode('UTF-8')
      puts "Save fixed tagname(#{tagname.inspect})"
      self.tagname = tagname # save the fixed version
      self.save
      raise 'Broken Encoding!' if not tagname.valid_encoding?
    end
    return tagname
  end

  def self.cleanup!(tag)
    tag.gsub!(%r{[<>/~\^,]}, '')
    tag.strip!
    tag.downcase!
  end
end

class DmUser
  has n, :items

  # optional
  property :username, String, :unique => true

  property :api_secret, String

  property :nsfw, Boolean, :default => false

  def to_ary
    [self]
  end
end

DataMapper.finalize
DataMapper.auto_upgrade!

#
# Helpers
# 

helpers do

  include Rack::Utils
  alias_method :h, :escape_html

  def truncate(s, len=30) 
    s[0...len] + (s.length > len ? '...' : '')
  end

  def partial(page, options={})
    unless @partials == false
      haml page, options.merge!(:layout => false)
    end
  end

  def api_request?
    request.accept.include? 'application/json'
  end

  def fileprefix
    "#{Time.now.strftime("%y%m%d%H%M%S")}_zeitgeist"
  end

  def pagination
    return if not @items or not @items.class.method_defined? :pager or not @items.pager
    @items.pager.to_html(request.fullpath, :size => 5)
  end

  def shorten(str)
    if str.length > 11
      "#{str[0..(10)]}..."
    else
      str
    end
  end

  def base_url
    url = request.url
    url[0...(url[8...-1].index('/') + 8)]
  end

  def random_token(length)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
    token = ''
    length.times do
      token += chars[rand(chars.length)]
    end
    token
  end

  def show_nsfw?(setting_only=false)
    if request.url.match %r{show(/tag)?/nsfw} and not setting_only
      true
    elsif not logged_in? and request.cookies['zg_show_nsfw'] == 'true'
      true
    elsif logged_in? and current_user.nsfw
      true
    else
      false
    end
  end

  def weighted_size(count, min, max)
    maxf = 37
    minf = 10
  
    # based on http://whomwah.com/2006/07/06/another-tag-cloud-script-for-ruby-on-rails/
    # thx;)
    spread = max.to_f - min.to_f
    spread = 1.to_f if spread <= 0
    fontspread = maxf.to_f - minf.to_f
    fontstep = spread / fontspread
    size = ( minf + ( count.to_f / fontstep ) ).to_i
    size = maxf if size > maxf

    size
  end

  def sqlite_adapter?
    defined? DataMapper::Adapters::SqliteAdapter and 
      repository(:default).adapter.class == DataMapper::Adapters::SqliteAdapter
  end

  def raw_sql(sql)
    repository(:default).adapter.select(sql)
  end

  def per_page
    if params.has_key? 'per_page' and params[:per_page].match /^\d+$/
      per_page = params[:per_page].to_i
      per_page = 200 if per_page > 200
    else
      per_page = settings.items_per_page
    end
    per_page
  end

end

#
# General Filters
# 
before do
  logger.datetime_format = "%Y/%m/%d @ %H:%M:%S "
  logger.level = 0

  if request.host =~ /^www\./
    redirect "#{request.scheme}://#{request.host.gsub('www.', '')}:#{request.port}", 301
  end

  # subdomains that specify a username constrain the items displayed
  @subdomain_user = nil
  if settings.subdomain_users
    if request.host.match /^([^\.]+)\.#{settings.domain}$/
      username = $1
      @subdomain_user = User.get(:conditions => ['UPPER(username) = ?', username.upcase])
      redirect "#{request.scheme}://#{settings.domain}:#{request.port}" if not @subdomain_user
    end
  end
 
  # X-Auth API authentication as specified in the documentation
  if request.env.has_key? 'HTTP_X_API_AUTH'
    email, api_secret = request.env['HTTP_X_API_AUTH'].split('|')
    user = User.get(:email => email)

    if not user or not user.api_secret
      raise 'user not found or no shared secret'
    end

    if api_secret == user.api_secret
      # authenticate current user
      session[:user] = user.id
    else
      raise 'invalid authentication'
    end
  end
end

#
# Routes
# 

get '/' do
  args = {
    :per_page => per_page,
    :order => [:id.desc]
  }

  if params.has_key? 'before'
    args.merge!(:conditions => ['items.id < ?', params[:before]])
  end
  if params.has_key? 'after'
    args.merge!(:conditions => ['items.id > ?', params[:after]])
  end
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  @items = Item.page(params[:page], args)

  if api_request?
    last_modified @items.first.created_at if @items.length > 0
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/similar/:type/:value' do
  if params[:type] == 'id'
    id = params[:value]
    fingerprint = Item.get(id).fingerprint
  elsif params[:type] == 'fp'
    fingerprint = params[:value].to_i
  else
    raise 'unrecognized type'
  end

  @items = []
  #@distances = {}
  Item.similar(fingerprint).each do |res|
    id = res[0]
    fingerprint = res[1]
    distance = res[2]
    @items << Item.get(id)
  end

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/random/?:type?' do
  @type = %w{image video audio}.include?(params[:type]) ? params[:type] : nil
  sql = 'SELECT id FROM items'
  where = []
  where << " type = '#{@type}'" if @type
  where << " dm_user_id = '#{@subdomain_user.id}'" if @subdomain_user
  sql << " WHERE #{where.join(' and ')}" if not where.empty?
  if sqlite_adapter?
    sql << ' ORDER BY RANDOM()'
  else
    sql << ' ORDER BY RAND()'
  end
  sql << " LIMIT #{per_page}"
  @items = Item.all(:id => raw_sql(sql))

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :random
  end
end

post '/update/nsfw' do
  nsfw = params['nsfw'] == 'true' ? true : false

  if logged_in?
    user = current_user.db_instance
    user.update({:nsfw => nsfw})
  else
    response.set_cookie("zg_show_nsfw", :value => nsfw,
                                        :domain => request.host,
                                        :path => '/',
                                        :expires => Time.now + 94608000)
  end
    
  content_type :json
  {:nsfw => nsfw}.to_json
end

get '/gallery/:user/?' do
  user = User.get(:username => params['user'])
  raise 'no user found with this username' if not user

  args = {
    :per_page => per_page,
    :dm_user_id => user.id,
    :order => [:created_at.desc]
  }
  if params.has_key? 'before'
    args.merge!(:conditions => ['items.id < ?', params[:before]])
  end
  if params.has_key? 'after'
    args.merge!(:conditions => ['items.id > ?', params[:after]])
  end
  @items = Item.page(params[:page], args)

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/show/:type' do
  type = params[:type]

  if %w{video audio image link}.include? type
    @title = "#{type.capitalize}s at #{settings.pagetitle}"
    args = {
      :per_page => per_page,
      :type => type,
      :order => [:created_at.desc]
    } 
    args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user
    @items = Item.page(params[:page], args)
  elsif type == 'nsfw'
    @title = "nsfw at #{settings.pagetitle}"
    args = {
      :per_page => per_page,
      :order => [:created_at.desc]
    }
    args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user
    @items = Item.page(params[:page], args)
  else
    raise 'show what?'
  end

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/show/tag/:tags' do
  @title = "#{@tag} at #{settings.pagetitle}"
  args = {
    :order => [:created_at.desc]
  }
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  if params.has_key? 'before'
    args.merge!(:conditions => ['items.id < ?', params[:before]])
  end
  if params.has_key? 'after'
    args.merge!(:conditions => ['items.id > ?', params[:after]])
  end

  tags = unescape params[:tags]
  if tags.include? '^'
    args.merge!(Item.tags.tagname => tags.split('^'))
    @items = Item.page(params[:page], args.merge(:per_page => per_page))
  else
    @items = tags.split(';').inject(Item.all) { |q, tag|
      q & Item.all(args.merge(Item.tags.tagname => tag))
    }.page(params[:page], :per_page => per_page)
  end

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/show/dimensions/:dimensions' do
  dimensions = params[:dimensions]
  @title = "#{dimensions} at #{settings.pagetitle}"

  args = {
    :type => 'image',
    :per_page => per_page,
    :dimensions => dimensions,
    :order => [:created_at.desc]
  }
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  @items = Item.page(params[:page], args)

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/show/ratio/:ratio' do
  ratio = params[:ratio]
  raise 'ratio syntax error(w:h)' if not ratio.match /([^:]+):(.*)/
  width = $1.to_f
  height = $1.to_f
  ratio_num = width / height

  dimensions = []
  Item.all(:type => 'image').aggregate(:dimensions).each do |dimension|
    next if not dimension
    if dimension.match /(\d+)x(\d+)/ and $1.to_i != 0 and $2.to_i != 0
      dimensions << dimension if ratio_num == ($1.to_f / $2.to_f)
    end
  end
  
  @title = "#{ratio} at #{settings.pagetitle}"
  args = {
    :type => 'image',
    :per_page => per_page,
    :dimensions => dimensions,
    :order => [:created_at.desc]
  }
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user
  @items = Item.page(params[:page], args)

  if api_request?
    content_type :json
    {:items => @items}.to_json
  else
    haml :index
  end
end

get '/list/tags' do
  @title = "Tags of #{settings.pagetitle}"
  @tags = Tag.all(:order => [:count.desc], :count.gt => 0, :tagname.not => nil)

  @min = @tags.min_by {|tag| tag.count}.count
  @max = @tags.max_by {|tag| tag.count}.count

  # show only tags of the current subdomain user
  if @subdomain_user
    @tags.delete_if do |tag|
      true if Item.count(:dm_user_id => @subdomain_user.id, Item.tags.tagname => tag.tagname) == 0
    end
  end

  if api_request?
    content_type :json
    {:tags => @tags}.to_json
  else
    haml :list_tags
  end
end

get '/list/dimensions/?:ratio?' do
  @title = "Image dimensions of #{settings.pagetitle}"
  dimensions = Item.all(:type => 'image').aggregate(:dimensions, :all.count)
  dimensions.delete_if do |dimension|
    true if dimension.last <= 1 or not dimension.first or not dimension.first.match /^\d+x\d+$/
  end

  # show only dimensions of the current subdomain user
  if @subdomain_user
    dimensions.delete_if do |dimension|
      true if Item.count(:dm_user_id => @subdomain_user.id, :dimensions => dimension.first) == 0
    end
  end

  dimensions.sort! do |a, b|
    b.last <=> a.last
  end

  #TODO: bug when dimensions are empty, catch this and fail gracefully
  @min = dimensions.min_by {|dimension| dimension.last}.last
  @max = dimensions.max_by {|dimension| dimension.last}.last

  @common_ratios = %w{16:9 16:10 4:3 3:2 5:4}

  @ratios = []
  @ratio = nil
  if params.has_key? 'ratio'
    @ratio = params['ratio']
    if @ratio.match /([^:]+):(.*)/
      @ratios = [@ratio]
      ratiow = $1.to_f
      ratioh = $2.to_f

      @dimensions = []
      dimensions.each do |pair|
        dimension = pair.first
        count = pair.last


        dimension.match /(\d+)x(\d+)/
        width = $1.to_f
        height = $2.to_f

        if (ratiow/ratioh) == (width/height)
          @dimensions << pair
        end
      end
    end
  else
    @dimensions = dimensions
  end

  @dimensions.each_index do |i|
    @dimensions[i].first.match /(\d+)x(\d+)/
    width = $1.to_i
    height = $2.to_i
    gcd = width.gcd height
    ratio = "#{width / gcd}:#{height / gcd}"
    @ratios << ratio
    @dimensions[i] << ratio
  end

  @ratios.uniq!

  if api_request?
    content_type :json
    {:ratio => @ratio, :dimensions => @dimensions}.to_json
  else
    haml :list_dimensions
  end
end

get '/about' do
  @title = "About #{settings.pagetitle}"
  if api_request?
    haml :about, :layout => false
  else
    haml :about
  end
end

get '/embed/:id' do
  item = Item.get(params['id'])
  item.embed
end

get '/search' do
  if not params.has_key? 'q'
    # show search form
    @title = "Search #{settings.pagetitle}"
    @query = 'search'
    @type = 'tags'
    if api_request?
      haml :search, :layout => false
    else
      haml :search
    end
  else
    # search results
    @query = params['q']
    @type = 'tags'
    if params.has_key? 'type' and %w{tags source title reverse}.include? params['type']
      @type = params['type']
    end

    @title = "Search for #{@type.capitalize} with #{@query} at #{settings.pagetitle}"
    args = {
      :per_page => per_page,
      :order => [:created_at.desc]
    }
    args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

    if params.has_key? 'before'
      args.merge!(:conditions => ['items.id < ?', params[:before]])
    end
    if params.has_key? 'after'
      args.merge!(:conditions => ['items.id > ?', params[:after]])
    end

    case @type
    when 'tags'
      args.merge!(Item.tags.tagname.like => "%#{@query}%")
    when 'source'
      args.merge!(:source.like => "%#{@query}%")
    when 'title'
      args.merge!(:title.like => "%#{@query}%")
    when 'reverse'
      if @query.match /^\d+$/ # ID
        args.merge!(:id => @query.to_i)
      elsif @query.match /(20\d{4}\/zg\.[^\.]+?)(?:_\d+)?(\.)(png|jpeg|gif)/
        args.merge!(:image.like => "%#{$~.captures.join}%")
      else
        args.merge!(:source.like => "%#{@query}%")
      end
    end

    @items = Item.page(params[:page], args)

    if api_request?
      content_type :json
      if @type == 'tags' # TODO: call this /searchtags or something else
        {:type => @type, :tags => Tag.all(:tagname.like => "%#{@query}%")}.to_json
      else
        {:type => @type, :items => @items}.to_json
      end
    else
      haml :search # display form and items
    end
  end
end

# TODO: rename to something else,
# this is only used for tag autocomplete/suggestions
# always returns json
post '/search' do
  query = params['q']
  args = {
    :per_page => per_page,
    :order => [:created_at.desc],
    Item.tags.tagname.like => "%#{query}%"
  }
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  if params.has_key? 'before'
    args.merge!(:conditions => ['items.id < ?', params[:before]])
  end
  if params.has_key? 'after'
    args.merge!(:conditions => ['items.id > ?', params[:after]])
  end

  @items = Item.page(params[:page], args)

  content_type :json
  {:type => type, :tags => Tag.all(:tagname.like => "%#{query}%")}.to_json
end

get '/new' do
  @title = "Upload something to #{settings.pagetitle}"
  if api_request?
    haml :new, :layout => false
  else
    haml :new
  end
end

# upload images/remote download urls
# params: tags, image_upload[], remote_url[], announce
post '/new' do
  tags = params.has_key?('tags') ? params['tags'] : ''
  uploads = params.has_key?('image_upload') ? params['image_upload'] : []
  remotes = params.has_key?('remote_url') ? params['remote_url'] : []
  titles = params.has_key?('title') ? params['title'] : []
  link = params.has_key?('link') ? (params['link'] == 'true' ? true : false) : false
  announce = params.has_key?('announce') ? (params['announce'] == 'true' ? true : false) : false
  fingerprint = params.has_key?('ignore_fingerprint') ? (params['ignore_fingerprint'] == 'true' ? 1 : nil) : nil

  # legacy (api) / depricated api
  if uploads.class != Array and uploads.class == Hash # just to make sure
    uploads = [ uploads ]
  end
  if remotes.class != Array and remotes.class == String
    remotes = [ remotes ]
  end

  # neiter upload nor remote? -> error
  if uploads.empty? and remotes.empty?
    raise 'You should select at least one upload or remote url!'
  end

  # process uploads and remote urls, stop if an error occured
  items = [] # Array of Item Objects
  tag_objects = [] # Array of Tag Objects
  begin

    while not uploads.empty? or not remotes.empty? 
      upload = uploads.pop
      remote = remotes.pop if not upload
      title = titles.pop

      # for upload use the tempfile as image and the orig. filename as source
      # for remote unset image and use the url as source
      image = upload ? upload[:tempfile].path : nil
      source = remote ? remote.strip : upload[:filename]

      # skip empty ones
      next if not image and source.empty?

      user_id = (logged_in?) ? current_user.id : nil
      if logged_in? and current_user.admin? and params.has_key?('as_username')
        user = User.get(:username => params['as_username'])
        if user
          user_id = user.id
        end
      end

      # the hook will perform the remote downloading and image processing
      item = Item.new(:title => title,
                      :image => image, 
                      :source => source, 
                      :type => link ? 'link' : nil,
                      :fingerprint => fingerprint,
                      :dm_user_id => user_id)
      if item.save
        item.add_tags(tags)
        items << item
        tag_objects = item.tags #i dont like this either
      else
        raise 'Item create error: ' + item.errors.full_messages.join(', ')
      end
    end

    # announce in irc:
    irc_settings = settings.irc_announce
    if irc_settings[:active] and announce and items.length > 0
      begin
        agent = Mechanize.new
        unless irc_settings[:ssl_verify]
          agent.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        args = {
          'username' => irc_settings[:username],
          'password' => irc_settings[:password],
          'command' => 'zg announce %d' % items.first.id
        }
        agent.post('%s/dispatch' % irc_settings[:uri], args)
      rescue
        logger.warn 'unable to announce in IRC: ' + $!.to_s
      end
    end

    if api_request?
      content_type :json
      {:items => items}.to_json
    else
      flash[:notice] = 'New item added successfully.'
      redirect '/'
    end

  rescue Exception => e

    logger.error "create error: #{e.class.to_s} #{e.to_s}"
    logger.error e.backtrace.join("\n")

    # only allow our own exceptions to be publicized
    return if not [RuntimeError, Exception, DuplicateError, RemoteError].include? e.class

    if e.class == DuplicateError
      item = Item.get e.id

      if not tags.empty?
        # add the tags incase there some new one:
        item.add_tags(tags)
      end
    end

    raise CreateItemError.new(e, items, tag_objects)

  end
end

get '/:id' do
  pass unless params[:id].match /^\d+$/
  @item = Item.get(params[:id])
  raise "no item found with id #{params[:id]}" if not @item

  if api_request? 
    content_type :json
    {:item => @item}.to_json
  else
    args = (not show_nsfw?) ? {:nsfw => false} : {}

    # next/prev items:
    @next = Item.all(args.merge(:id.gt => @item.id, :order => [:id.asc])).first
    @prev = Item.all(args.merge(:id.lt => @item.id, :order => [:id.desc])).first

    haml :item
  end
end

# adds or removes tags from an item, update items title
post '/update' do
  id = params[:id]
  add_tags = (params[:add_tags] || '').split(',')
  del_tags = (params[:del_tags] || '').split(',')

  # move add tags beginning with - to del_tags
  add_tags.each do |tag|
    if tag.match /^-(.*)$/
      del_tags << $1
      add_tags.delete tag
    end
  end

  # get the item to edit
  @item = Item.get(id)
  raise "item with id #{id} not found!" if not @item

  if params.has_key? 'title'
    title = params[:title]
    @item.update(:title => title)
  end

  # add tags (create them if not exists)
  added_tags = @item.add_tags(add_tags)
  deleted_tags = @item.del_tags(del_tags)

  if api_request?
    content_type :json
    {:item => @item}.to_json
  else
    redirect '/'
  end
end

# claim ownership of an anonymously posted item
post '/claim' do
  raise 'needs authentication' if not logged_in?

  id = params[:id]
  item = Item.get(id)
  raise "item with id #{id} not found!" if not item

  if item.dm_user_id
    user = User.get(item.dm_user_id)
    raise "item already owned by #{item.dm_user_id} #{user.username}"
  end
  
  item.update(:dm_user_id => current_user.id)

  if api_request?
    content_type :json
    {:id => id}.to_json
  else
    flash[:notice] = "Item ##{id} claimed."
    redirect params['return_to']
  end
end

post '/delete' do
  item = Item.get(params[:id])
  raise 'item not found' if not item
  if item.dm_user_id == current_user.id or current_user.admin?
    item.destroy
    if api_request?
      content_type :json
      {:id => item.id}.to_json
    else
      flash[:notice] = "Item ##{params[:id]} is gone now."
      redirect params['return_to']
    end
  else
    raise 'Y U NO AUTHENTICATE?'
  end
end

get '/api_secret/qrcode.png' do
  user = current_user.db_instance
  if settings.qrcode[:active] and defined? QREncoder
    api_secret = user.api_secret
    qrcode_data = '%s#auth:%s|%s' % [base_url, user.email, api_secret]
    qrcode = QREncoder.encode(qrcode_data)
    content_type :png
    return qrcode.png(:pixels_per_module => 6).to_blob
  end
  raise 'qrcode deactivated'
end

get '/api_secret/?:regenerate?' do
  if not logged_in?
    redirect '/login'
  end

  @qrcode_active = (settings.qrcode[:active] and defined? QREncoder)

  user = current_user.db_instance
  if not user.api_secret or params[:regenerate]
    @api_secret = random_token 48
    user.update({:api_secret => @api_secret})
  else
    @api_secret = user.api_secret
  end
  @redirect = params[:redirect]

  if api_request?
    content_type :json
    {email: user.email, api_secret: @api_secret, user_id: current_user.id}.to_json
  else
    haml :api_secret
  end
end

# public stats and diagrams for this zeitgeist installation
get '/stats' do
  # some stats in numbers
  # the rest is loaded from stats.json
  args = {}
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  @stats = {
    :total => Item.count(args),
    :image => Item.count(args.merge(:type => 'image')),
    :audio => Item.count(args.merge(:type => 'audio')),
    :video => Item.count(args.merge(:type => 'video')),
    :user => DmUser.count
  }

  haml :stats
end

get '/stats.json' do
  logger.debug 'Generating stats json object'

  def count_by(date)
    counts = []
    if sqlite_adapter?
      format_sql = 'strftime("%s", created_at)' % date
    else
      format_sql = "DATE_FORMAT(created_at, '%s')" % date
    end
    sql = 'SELECT %s AS date, COUNT(*) AS count FROM items' % format_sql
    sql << ' WHERE dm_user_id = %d' % @subdomain_user.id if @subdomain_user
    sql << ' GROUP BY date ORDER BY created_at asc;'
    res = raw_sql(sql)
    logger.debug('Generate stats with custom SQL returned %d results.' % res.length)
    res.each do |row|
      counts << [row.date, row.count]
    end
    return counts
  end

  years = count_by '%Y'
  months = count_by '%Y-%m'
  days = count_by '%Y-%m-%d'

  # user statistics
  user_stats = []
  User.all.each do |user|
    name = user.username ? user.username : '?'
    count = user.items.count
    user_stats << [name, count] if count > 0
  end
  # user_stats << ['anonymous', Item.count(:dm_user => nil)]

  content_type :json
  {
    :years => years,
    :months => months,
    :days => days,
    :image => Item.count(:type => 'image'),
    :audio => Item.count(:type => 'audio'),
    :video => Item.count(:type => 'video'),
    :user => user_stats
  }.to_json
end

get '/feed/tag/:tag' do
  tag = unescape params[:tag]
  @title = "#{tag} at #{settings.pagetitle}"
  @base = request.url.chomp(request.path_info)

  args = {
    :limit => settings.feed_max,
    Item.tags.tagname => tag,
    :order => [:created_at.desc]
  }
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  @items = Item.all(args)

  content_type :xml
  haml :feed, :layout => false, :format => :xhtml
end

get %r{/feed(/nsfw)?} do
  nsfw = params[:captures] ? true : false

  @base = request.url.chomp(request.path_info)

  args = {
    :limit => settings.feed_max
  }
  args.merge!(:dm_user_id => @subdomain_user.id) if @subdomain_user

  if nsfw
    @items = Item.all(args.merge(:order => [:created_at.desc]))
  else
    @items = Item.all(args.merge(:nsfw => false, :order => [:created_at.desc]))
  end

  content_type :xml
  haml :feed, :layout => false, :format => :xhtml
end

get '/favicon.ico' do
  redirect '/images/favicon.png'
end

def handle_error
  error = env['sinatra.error']
  code = (response.status == 200) ? 500 : response.status

  # Log exception that occured:
  logger.error "Error Handler: #{error.inspect}"
  logger.error "Backtrace: " + error.backtrace.join("\n")
  if error.class == RemoteError
    logger.error "Error Handler: #{error.error.inspect}"
    logger.error "Backtrace: " + error.error.backtrace.join("\n")
  end

  # only allow our own exceptions to be publicized
  if not [Sinatra::NotFound, RuntimeError, StandardError, CreateItemError].include? error.class
    error = RuntimeError.new 'unknown error occured'
  end

  if api_request? 
    status code
    content_type :json
    error.to_json

  elsif request.get?
    status code
    @error = error.message
    @code = code.to_s
    haml :error, :layout => false 

  else
    flash[:error] = error.message
    redirect '/'

  end
end

error 400..510 do # error RuntimeError do
  handle_error
end

error Exception do
  handle_error
end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end

