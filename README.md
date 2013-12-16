Zeitgeist
=========

Zeitgeist is a free software media gallery built with [Sinatra](http://www.sinatrarb.com).

See it in action: [zeitgeist.li](http://zeitgeist.li).

This is work in progress, come and join the fun!


Current Features
----------------

* Upload image files -or-
* Submit URLs to remote images and videos
* Remote plugins:
  * Image hoster URLs are detected and parsed for the image: abload, flickr, fukung, imagenetz, imageshack, imgur, picpaste, twitpic, twitter, xkcd, yfrog (easily extendable)
  * Video and Audio URLs are also detected for the following sites: YouTube, Vimeo, Soundcloud (this also parses and stores thumbnails along with title and tags)
* Items (images, audio and videos) can be tagged and autotagged by url patterns aswell
* User registration and authentication
* Registered users can delete items they submitted
* The [pHash](http://www.phash.org/) (perceptual hash) library (and [phashion](https://github.com/mperham/phashion) ruby bindings) is used to detect duplicate submissions and is able to detect similar images that are reencoded or slightly manipulated.
* API: a simple HTTP API can be used to access zeitgeist ([documented here](https://github.com/jessor/zeitgeist/wiki/API-Documentation))
* [IRC](https://github.com/4poc/rbot-plugins/blob/master/zg.rb): a rubybot plugin allows to access zeitgeist in many ways:
  * auto-submit urls posted in channels
  * multi-user authentication
  * query item information like parsed title and tags
  * tag, delete (own) items through the IRC interface
* [Android](https://github.com/4poc/zeitgeist-android): the app is currently in development, but the current features are:
  * Endless scrolling through the gallery
  * View images directly and use the YouTube app to watch videos
  * Modify item taggings, including an autocompletion for tags
  * Share photos from your gallery or make a snapshot and upload it directly from the app
  * Authenticate with your zeitgeist account easily using a qrcode shown on the [/api_secret](http://zeitgeist.li/api_secret) page. (this uses the [zxing barcode scanner](http://code.google.com/p/zxing))
  * Delete your own photos from the gallery

Development
-----------

* Use rvm or similar to install ruby 2.0.0
* `git clone https://github.com/jessor/zeitgeist.git zeitgeist/`
* `cd zeitgeist/`
* `gem install bundler`
* `bundle install` Install requirements, this step requires some system libraries.
* `cp config.yaml.sample config.yaml`
* `ruby zeitgeist.rb` Or use shotgun, thin, or similar.

Acknowledgements
----------------

* Form Icons: [Dat Nguyen](http://splashyfish.com/), [Iconfinder](http://www.iconfinder.com/search/?q=iconset%3AsplashyIcons)
* Clock, Audio Icon: [Alexandre Moore](http://sa-ki.deviantart.com/), [Iconfinder](http://www.iconfinder.com/search/?q=iconset%3Anuove)
* Header Ribbon: [Damion Yeatman](http://twitter.com/#!/DamYeatman), [Forrst](http://forrst.com/posts/CSS3_Ribbon-DcL)


Licence
-------

Zeitgeist is licensed under the GPLv2+. Please drop me a line if you use or modify it :)
