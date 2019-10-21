$LOAD_PATH << File.expand_path('./lib')
require 'auth'
require 'bot'
require 'health'
require 'sucker_punch'
require 'rack'

SuckerPunch.logger = Logger.new(STDERR)
SuckerPunch.logger.level = :info

# Initialize the app and create the API (bot) and Auth objects.
run Rack::Cascade.new [Health, Auth, API]
