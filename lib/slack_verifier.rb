# frozen_string_literal: true

require 'rack'
require 'slack-ruby-client'

class SlackVerifier
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      rq = SlackHttpRequest.new(env)
      slackRequest(rq).verify!
      rq.body.rewind
      @app.call(env)
    rescue Slack::Events::Request::MissingSigningSecret, Slack::Events::Request::InvalidSignature, Slack::Events::Request::TimestampExpired => err
      env[Rack::RACK_LOGGER].info("unauthorised request received, err=#{err}")
      env[Rack::RACK_LOGGER].info(debug_hash(rq).to_json)
      return Rack::Response.new([], 403, {}).finish
    end
  end

  def slackRequest(rq)
    Slack::Events::Request.new(rq)
  end

  def debug_hash(rq)
    rq.body.rewind
    {
      timestamp: rq.headers[SlackHttpRequest::X_SLACK_REQUEST_TIMESTAMP],
      signature: rq.headers[SlackHttpRequest::X_SLACK_SIGNATURE ],
      body: rq.body.read
    }
  end
end

class SlackHttpRequest
  X_SLACK_REQUEST_TIMESTAMP = 'X-Slack-Request-Timestamp'
  X_SLACK_SIGNATURE = 'X-Slack-Signature'

  attr_reader :headers, :body

  def initialize(env)
    @request = Rack::Request.new(env)
    @headers = {
      X_SLACK_REQUEST_TIMESTAMP => @request.get_header(env_header(X_SLACK_REQUEST_TIMESTAMP)),
      X_SLACK_SIGNATURE => @request.get_header(env_header(X_SLACK_SIGNATURE))
    }
    @body = @request.body
    @body.rewind
  end

  private

  def env_header(s)
    "HTTP_#{s}".tr('-','_').upcase
  end
end
