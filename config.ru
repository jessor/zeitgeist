require 'rubygems'
require 'bundler'
require 'sinatra'
require 'zeitgeist'

Bundler.require
set :run => false

run Sinatra::Application
