
require 'json'

module Sinatra::Remote

module Plugins

  # Default Plugin for pre-download processing
  # This plugin is used for all urls with the exception of urls
  # that are matched by an plugin pattern (plugin constant PATTERN)
  # Plugins for specific sites may scrape for the real image
  # url and/or for other content like tags or titles.
  class Plugin
    TYPE = 'image' 

    AUTOTAGGING = {
      'xkcd.com' => ['comic', 'xkcd'],
      'explosm.net' => ['comic', 'explosm'] # , 'cyanide & happiness']
    }

    def self.pattern_test(pattern, url)
      return false if not url
      if pattern.class == String
        host = URI.parse(url).host
        return true if host.to_s.include? pattern
      elsif url.match pattern 
        return true
      end
    end

    # initialize with the original remote url
    # this default plugin assumes an image/ resource
    def initialize(orig_url)
      @orig_url = orig_url
    end

    def type
      self.class::TYPE
    end

    # original url (can point to html page)
    def orig_url
      @orig_url
    end

    # should return url to an image/png,jpg,gif file
    # or nil if there isn't one (image/audio without preview pic)
    def url
      # defines the default behaviour: no change in remote image url
      # other remote plugins may overwrite this behaviour and scrape
      # the image link from html (along other information)
      @orig_url
    end

    # the extracted content title or original filename
    def title
    end

    def tags
      AUTOTAGGING.each_pair do |pattern, new_tags|
        if Plugin::pattern_test(pattern, self.url) or
          Plugin::pattern_test(pattern, self.orig_url) 
           return new_tags 
        end
      end
      []
    end
    
    # per default allow any tags to be added, sometimes this
    # is not desirable (youtube tagspam)
    def only_existing_tags
      false
    end

    def embed(width=640, height=385)
      OEmbed::Providers.get(@orig_url, :maxwidth=>width, :maxheight=>height).html
    end

    private

    # allow plugins to use mechanize for scraping urls, tags etc.
    def agent
      if not @agent
        @agent = Mechanize.new
        if settings.remote_proxy_host
          @agent.set_proxy(
            settings.remote_proxy_host,
            settings.remote_proxy_port, 
            settings.remote_proxy_user, 
            settings.remote_proxy_pass 
          )
        end
        @agent.user_agent = settings.agent
      end
      @agent
    end

    def json(url = nil)
      url = self.orig_url if not url
      if not @json
        @json = agent.get url
      end
      JSON.parse @json.body
    end

    def get(url = nil)
      url = self.orig_url if not url
      if not @page
        @page = agent.get url
      end
      if @page.class != Mechanize::Page # text/html
        @page = nil
      else
        @page
      end
    end

    def scan(pattern)
      # implicit fetch the page of the url
      get if not @page
      return if not @page

      result = @page.body.scan pattern
      if not result or result.empty?
        puts "url scraping failed regex matching of '#{pattern}' for #{@url}"
        return []
      end

      return result
    end

    def match(pattern)
      get if not @page
      return if not @page
      scan(pattern).first || []
    end

    def match_one(pattern)
      get if not @page
      return if not @page
      match(pattern).first || ''
    end

    def search(selector)
      # implicit fetch the page of the url
      get if not @page
      return if not @page

      result = @page.search selector
      if not result
        puts "url scraping failed parsing of '#{selector}' for #{@url}"
        return []
      end

      return [] if result.length == 0

      # convert to simple array of strings
      result = result.map do |elem|
        case elem
        when Nokogiri::XML::Text
          elem.content
        when Nokogiri::XML::Attr
          elem.value
        else
          elem
        end
      end

      return result
    end

    def search_one(selector)
      get if not @page
      return if not @page
      search(selector).first || '' 
    end

    def og_search(property)
      get if not @page
      return if not @page
      search_one 'meta[@property="og:' + property + '"]/@content' 
    end

  end # end class plugin

  class Loader
    @@loaded_plugins = nil

    def self.create(url, plugin_name=nil)
      return nil if not url =~ URI::regexp 

      if not @@loaded_plugins
        @@loaded_plugins = []
        puts 'Load availible plugins in /lib/remote/plugins'
        Dir[File.dirname(__FILE__)+'/plugins/*.rb'].map do |plugin_path|
          plugin_module = Module.new
          plugin_file = File.basename plugin_path
          # bindtextdomain_to(plugin_module, File.basename(plugin_file))
          begin
            plugin_content = IO.read plugin_path
            plugin_module.module_eval(plugin_content, plugin_file)
            plugin_module::constants.each do |const|
              plugin_class = plugin_module::const_get const

              next if not plugin_class < Plugin

              @@loaded_plugins << plugin_class
            end
          rescue Exception => e
            puts "Error loading plugin #{plugin_file}: #{e.message}"
            puts e.backtrace
          end
        end
      end

      # select and return the plugin to use based on the pattern
      @@loaded_plugins.each do |plugin|
        return plugin.new(url) if plugin_name and plugin_name == plugin.name.split('::').last
        pattern = plugin.const_get 'PATTERN' rescue nil
        if pattern
          next if not Plugin::pattern_test(pattern, url)
        elsif plugin.name != 'Generic'
          puts "warning! plugin without PATTERN ignored!"
          next
        end
        puts "Use plugin: #{plugin.inspect}"
        return plugin.new url
      end
      return Plugin.new url
    end
  end

end # Plugins

end # Sinatra::Remote

