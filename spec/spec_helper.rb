ENV['RACK_ENV'] = 'test'

require 'rack/test'
require 'sinatra'

require './app'

RSpec.configure do |config|
  config.include Rack::Test::Methods
end

def app
  Sinatra::Application
end
