require './zeitgeist.rb'

map '/static' do
  environment = Sprockets::Environment.new

  ["static", "vendor/bootstrap-sass/vendor/assets"].map do |a|
    ["javascripts", "stylesheets", "images"].map do |b|
      environment.append_path File.join(a, b)
    end
  end

  Sprockets::Helpers.configure do |config|
    config.environment = environment
    config.prefix      = '/static'
    config.digest      = false
  end

  run environment
end

map '/' do
  run Sinatra::Application
end
