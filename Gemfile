source :rubygems

gem "dm-core"
gem "dm-pager"
gem "dm-validations"
gem "dm-timestamps"
gem "dm-migrations"
gem "dm-serializer"

gem "sinatra", "<= 1.3.3"
gem "shotgun"
gem "haml"
gem "sass"
gem "rack"
gem "rack-flash3", :require => "rack-flash"
gem "rack-pagespeed", :git => 'git://github.com/jessor/rack-pagespeed.git'
gem "sinatra-authentication"

gem "thin"

gem "builder", ">= 2.1.2"
gem "ruby-filemagic", :require => "filemagic" 
gem "mini_magick"
gem "mechanize"
gem "ruby-oembed", :require => "oembed" #, :git => 'git://github.com/jessor/ruby-oembed.git'

# qrencoder and phashion are optional features use
#   bundle install --without qrencoder/phashion if you don't want it

group :qrencoder do
  # QRCodes are used to quickly set the url, email and api secret in the
  # android application it requires the libqrencoder library to be installed
  # in the system.
  gem "qrencoder"
end

group :phashion do
  gem "phashion", :git => 'git://github.com/4poc/phashion.git'
end

# dependent on your database configuration:

group :sqlite do
    gem "dm-sqlite-adapter"
end

group :mysql do
    gem "dm-mysql-adapter"
end

