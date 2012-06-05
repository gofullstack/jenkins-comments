require 'bundler/setup'
Bundler.require(:default)

require './app'
run Sinatra::Application

