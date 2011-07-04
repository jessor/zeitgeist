require 'rubygems'
require 'bundler'
require 'sinatra'
require './zeitgeist.rb'

Bundler.require
set :run => false

run Sinatra::Application
