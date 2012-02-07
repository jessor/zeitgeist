require './zeitgeist.rb'

map '/static' do
    environment = Sprockets::Environment.new
    environment.append_path 'static/javascripts'
    environment.append_path 'vendor/bootstrap-sass/vendor/assets/javascripts'
    run environment
end

map '/' do
    run Sinatra::Application
end
