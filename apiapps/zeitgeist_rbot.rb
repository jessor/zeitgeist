# debug __FILE__
# require './zeitgeist_api.rb'

module ::Zeitgeist

  # stack with recently added items via irc, does not store items
  # added via web, thus relative offsets only affects these items 
  class ItemHistory
    def initialize
      @items = []
      @max_size = 100
    end

    # make sure item is new otherwise old item will be overwritten (by id)
    def <<(item)
      return if not item or item.class != Item
      while @items.length > @max_size
        @items.shift
      end
      debug "history size: #{@items.length}"

      @items.each_index do |i|
        if item.id == @items[i].id 
          @items[i] = item 
          return
        end
      end

      @items << item
    end

    def by_id_or_offset(id) 
      if id < 0
        by_offset id
      else
        by_id id
      end
    end

    def by_id(id)
      @items.each do |item|
        return item if item.id == id
      end
      return nil
    end

    def by_offset(offset)
      @items[offset]
    end

    def length
      @items.length
    end
  end

end # Zeitgeist module

class ZeitgeistBotPlugin < Plugin
  #
  # patterns used to match public channel messages for urls etc.
  #
  
  # ignore messages altogether that match with this
  PATTERN_OPT_OUT = /^(#|\/\/|\/\*)/

  # scan messages for urls by this pattern
  PATTERN_LISTEN_URL = %r{(http[s]?://[^ \)\}\]]+)}

  # match messages (that include urls) for tags list with this pattern
  # match groups: tags list (see self.parse_tags_list)
  PATTERN_LISTEN_TAGS = %{^[^#]+[#] ([^#]+)[#]?[^#]+$}

  # parse messages for operators with this pattern
  # match groups: item offset or id (default: -1), tags list (optional)
  PATTERN_LISTEN_OP = %r{^[\^|~](-?[0-9]+)? ?(.*)?$}

  Config.register(Config::StringValue.new('zeitgeist.base_url',
      :default => 'http://localhost/',
      :desc => 'Url to zeitgeist installation.'))
  Config.register(Config::StringValue.new('zeitgeist.api_secret',
      :default => 'changeme',
      :desc => 'Secret API key to allow to delete tags.')) # may change in future
  Config.register(Config::ArrayValue.new('zeitgeist.listen_channels',
      :default => [], :desc => 'Channels the bot should listen for urls'))
  Config.register(Config::ArrayValue.new('zeitgeist.log_destination',
      :default => [], :desc => 'Channels or nicks the bot should sent listen log messages'))

  def initialize
    super
    if @registry.has_key? :zeitgeist
      @source_history = Marshal::load(@registry[:zeitgeist]) 
      debug "use stack from registry (length:#{@source_history.length})"
    end
    if not @source_history
      debug 'use empty source_history'
      @source_history = {} #  Stack.new
    end
    @api = Zeitgeist::ZeitgeistAPI.new(@bot.config['zeitgeist.base_url'],
                                       @bot.config['zeitgeist.api_secret'])
  end

  def save
    @registry[:zeitgeist] = Marshal::dump(@source_history)
  end

  #
  # public bot commands
  #
  def cmd_item_new(m, params)
    url, tags = params[:url], params[:tags].join(' ')
    m.reply item_new(m.channel || m.source, url, tags, m.source.nick)
  end

  def cmd_item_tags_edit(m, params)
    id, tags = params[:index].to_i, params[:tags].join(' ')
    m.reply item_tags_edit(m.channel || m.source, id, tags)
  end

  def cmd_item_get(m, params)
    id = params[:index].to_i
    m.reply item_get(m.channel || m.source, id)
  end

  # listens to all messages in channel list for new urls to 
  # add or operators to edit item tags. 
  def message(m)
    response = nil
    return if m.address? or not @bot.config['zeitgeist.listen_channels'].include? m.channel.to_s

    message = m.message.strip
    channel = m.channel.to_s
    source = m.source.to_s

    # opt-out this message
    if message =~ PATTERN_OPT_OUT
      debug "opt-out message [#{source}/#{channel}] #{message}"
      return
    end

    # scan message for links ...
    urls = message.scan(PATTERN_LISTEN_URL)
    debug "message (#{message}) pattern match PATTERN_LISTEN_URL: #{urls.inspect}"
    urls.each do |url|
      # ... and tags:
      if urls.length == 1 and message.match PATTERN_LISTEN_TAGS
        debug "message (#{message}) pattern match PATTERN_LISTEN_TAGS: #{$1}"
        tags = $1
      end

      response = item_new(channel, url, tags, source) 

      debug "[#{source}/#{channel}] #{response}"

      return if response =~ /no image signature found/

      if response =~ /Duplicate/
        # .blame/lart?
      end
    end

    # parse op
    if message.match PATTERN_LISTEN_OP
      offset_or_id = $1 ? $1.strip : ''
      tags = $2 ? $2.strip : ''
      offset_or_id = -1 if offset_or_id.empty?
      offset_or_id = offset_or_id.to_i if offset_or_id.class == String

      debug "op [#{channel}/#{source}] off/id:#{offset_or_id} tags:#{tags.inspect}"

      if tags.empty? # get item 
        response = item_get(channel, offset_or_id)
        m.reply response
      else
        response = item_tags_edit(channel, offset_or_id, tags)
        m.reply response
      end
      response = nil # no need to log

    end
    
    if response
      @bot.config['zeitgeist.log_destination'].each do |dest|
        @bot.say(dest, "[#{source}/#{channel}] #{response}") 
      end
    end

  end

  private

  def item_new(source, url, tags, nick)
    history = history_by_source source
    begin
      item = Zeitgeist::Item::new_create(@api, url, tags)
      history << item
      return item.to_s
    rescue Exception => e
      debug e.inspect
      debug $@.join "\n"
      return e.message
    end
  end

  def item_tags_edit(source, id, tags)
    history = history_by_source source
    if (item = history.by_id_or_offset id)
      item_or_id = item
    else
      item_or_id = id
    end

    add, del = parse_tags_list(tags)
    debug "zeitgeist add/delete tags: add:#{add.inspect} del:#{del.inspect}"

    begin
      item = Zeitgeist::Item::edit_tags(@api, item_or_id, add, del)
      history << item # NOTE: this may overwrite old items based on their id!
      return item.to_s
    rescue Exception => e
      debug e.inspect
      debug $@.join "\n"
      return e.message
    end
  end
  
  def item_get(source, id)
    history = history_by_source source
    if not (item = history.by_id_or_offset id)
      begin
        item = Zeitgeist::Item::new_existing(@api, id)
        history << item
        return item.to_s
      rescue Exception => e
        debug e.inspect
        debug $@.join "\n"
        return e.message
      end
    else
      return item.to_s
    end
  end

  def history_by_source(source)
    if not @source_history.has_key? source
      @source_history[source] = Zeitgeist::ItemHistory.new
    end
    @source_history[source] 
  end

  def parse_tags_list(tags)
    add = []
    del = []

    tags.split(',').each do |tag|
      tag.strip!
      next if tag.empty?
      if tag.match /^([\-|+]?)(.*)$/
        next if not $2 or $2.empty?

        if $1 == '-'
          del << $2.strip
        else
          add << $2.strip
        end
      end
    end
    [add, del]
  end


end

plugin = ZeitgeistBotPlugin.new
plugin.map('zeitgeist get :index', 
           :threaded => true, 
           :action => 'cmd_item_get')
plugin.map('zeitgeist add :url [*tags]', 
           :defaults => {:tags => ''},
           :threaded => true, 
           :action => 'cmd_item_new')
plugin.map('zeitgeist tag :index *tags', 
           :threaded => true, 
           :action => 'cmd_item_tags_edit')

