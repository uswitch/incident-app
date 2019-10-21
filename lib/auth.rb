require 'sinatra/base'
require 'slack-ruby-client'
require 'uri'
require 'incident'

def get_random_string(length=7)
  source=("a".."z").to_a + (0..9).to_a
  key=""
  length.times{ key += source[rand(source.size)].to_s }
  return key
end

# Load Slack app info into a hash called `config` from the environment variables assigned during setup
SLACK_CONFIG = {
  slack_client_id: ENV['SLACK_CLIENT_ID'],
  slack_api_secret: ENV['SLACK_API_SECRET'],
  slack_redirect_uri: ENV['SLACK_REDIRECT_URI'],
}

# Check to see if the required variables listed above were provided, and raise an exception if any are missing.
missing_params = SLACK_CONFIG.select { |key, value| value.nil? }
if missing_params.any?
  error_msg = missing_params.keys.join(", ").upcase
  raise "Missing Slack config variables: #{error_msg}"
end

# Set the scope, all the things we'll need to access. See: https://api.slack.com/docs/oauth-scopes for more info.
BOT_SCOPE = 'bot,channels:write,chat:write:bot,channels:read,channels:history,users:read'

# This hash will contain all the info for each authed team, as well as each team's Slack client object.
# In a production environment, you may want to move some of this into a real data store.
$teams = {}

# Since we're going to create a Slack client object for each team, this helper keeps all of that logic in one place.
def create_slack_client(slack_api_secret)
  Slack.configure do |config|
    config.token = slack_api_secret
    fail 'Missing API token' unless config.token
  end
  Slack::Web::Client.new
end

# Slack uses OAuth for user authentication. This auth process is performed by exchanging a set of
# keys and tokens between Slack's servers and yours. This process allows the authorizing user to confirm
# that they want to grant our bot access to their team.
# See https://api.slack.com/docs/oauth for more information.

class Auth < Sinatra::Base
  configure do
    enable :logging
    set :logging, Logger::INFO
  end

  # If a user tries to access the index page, redirect them to the auth start page
  get '/' do
    redirect '/begin_auth'
  end

  # This page shows the user what our app would like to access and what bot user we'd like to create for their team.

  get '/begin_auth' do
    redirect_uri = URI.parse(SLACK_CONFIG[:slack_redirect_uri])
    if params[:a]
      redirect_uri.query = "a=#{params[:a]}"
    end
    redirect "https://slack.com/oauth/authorize?scope=#{BOT_SCOPE}&client_id=#{SLACK_CONFIG[:slack_client_id]}&redirect_uri=#{redirect_uri}"
  end


  # OAuth Step 2: The user has told Slack that they want to authorize our app to use their account, so
  # Slack sends us a code which we can use to request a token for the user's account.

  get '/finish_auth' do

    main_channel_id = ENV['SLACK_CHANNEL_ID']

    redirect_uri = URI.parse(SLACK_CONFIG[:slack_redirect_uri])
    if params[:a]
      redirect_uri.query = "a=#{params[:a]}"
    end
    client = Slack::Web::Client.new
    # OAuth Step 3: Success or failure
    begin
      response = client.oauth_access(
        {
          client_id: SLACK_CONFIG[:slack_client_id],
          client_secret: SLACK_CONFIG[:slack_api_secret],
          redirect_uri: redirect_uri,
          code: params[:code] # (This is the OAuth code mentioned above)
        }
      )

      # authorizes the app to access slack.
      team_id = response['user_id']


      client = create_slack_client(response['access_token'])
      user_id = response[:user_id]

      $teams[user_id] = {
        user_access_token: response['access_token'],
        bot_user_id: response['bot']['bot_user_id'],
        bot_access_token: response['bot']['bot_access_token']
      }
      $teams[user_id]['client'] = client

      # Be sure to let the user know that auth succeeded.
      status 200
      body 'Yay! Auth succeeded!'
      if params[:a] == 'start'
        incident = Incident.new(logger)
        incident.start(user_id, main_channel_id)
      end

    rescue Slack::Web::Api::Error => e
      # Failure:
      status 403
      body "status 403<br/>"
    end
  end
end
