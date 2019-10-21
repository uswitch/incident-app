require 'sinatra/base'

class Health < Sinatra::Base
  get '/healthz' do
    status 200
    "ok"
  end
end
