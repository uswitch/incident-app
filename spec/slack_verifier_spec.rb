# frozen_string_literal: true

require 'slack_verifier'

RSpec.describe SlackHttpRequest, '#new' do
  let(:env) do
    {
      'HTTP_X_SLACK_SIGNATURE' => 'a_signature',
      'HTTP_X_SLACK_REQUEST_TIMESTAMP' => 'a_timestamp',
      'rack.input' => StringIO.new('Ooh super request body')
    }
  end

  context 'request body' do
    it 'should return the request body when read' do
      rq = SlackHttpRequest.new(env)
      expect(rq.body.read).to eq('Ooh super request body')
    end
  end

  context 'headers' do
    it 'should return a set of headers including X-Slack-Signature' do
      rq = SlackHttpRequest.new(env)
      expect(rq.headers).to include(
        'X-Slack-Signature' => 'a_signature'
      )
    end

    it 'should return a set of headers including X-Slack-Request-Timestamp' do
      rq = SlackHttpRequest.new(env)
      expect(rq.headers).to include(
        'X-Slack-Request-Timestamp' => 'a_timestamp'
      )
    end
  end
end

RSpec.describe SlackVerifier, '#call' do
  let(:signing_secret) { 'ade6ca762ade4db0e7d31484cd616b9c' }
  let(:signature) { 'v0=91177eea054d65de0fc0f9b4ec57714307bc0ce2c5f3bf0d28b1b720c8f92ba2' }
  let(:timestamp) { '1547933148' }
  let(:body) do
    StringIO.new('{"token":"X34FAqCu8tmGEkEEpoDncnja","challenge":' \
            '"P7sFXA4o3HV2hTx4zb4zcQ9yrvuQs8pDh6EacOxmMRj0tJaXfQFF","type":"url_verification"}')
  end

  let(:logger) { double('logger') }

  let(:env) do
    {
      'HTTP_X_SLACK_SIGNATURE' => signature,
      'HTTP_X_SLACK_REQUEST_TIMESTAMP' => timestamp,
      'rack.input' => body,
      'rack.logger' => logger
    }
  end

  let(:ok_result) { 'OK!' }
  let(:app) do
    double(call: ok_result)
  end

  before do
    Slack::Events.configure do |config|
      config.signing_secret = signing_secret
      config.signature_expires_in = 30
    end
  end

  after do
    Slack::Events.config.reset
  end

  context 'with correct time' do
    before do
      Timecop.freeze(Time.at(timestamp.to_i))
    end

    after do
      Timecop.return
    end

    context 'and correct signing secret and signature' do
      it 'should call the app and get OK!' do
        verifier = SlackVerifier.new(app)
        expect(verifier.call(env)).to eq(ok_result)
      end
    end

    context 'and invalid signature' do
      let(:signature) { 'not_a_valid_signature' }

      it 'should return 403' do
        expect(logger).to receive(:info).with(/Slack::Events::Request::InvalidSignature/)
        expect(logger).to receive(:info)
        verifier = SlackVerifier.new(app)
        expect(verifier.call(env)).to include(403)
      end
    end

    context 'and incorrect body' do
      let(:body) { StringIO.new('not_the_signed_body') }

      it 'should return 403' do
        expect(logger).to receive(:info).with(/Slack::Events::Request::InvalidSignature/)
        expect(logger).to receive(:info)
        verifier = SlackVerifier.new(app)
        expect(verifier.call(env)).to include(403)
      end
    end

    context 'and missing signing secret' do
      before do
        Slack::Events.configure do |config|
          config.signing_secret = nil
          config.signature_expires_in = 30
        end
      end

      after do
        Slack::Events.config.reset
      end

      it 'should return 403' do
        expect(logger).to receive(:info).with(/Slack::Events::Request::MissingSigningSecret/)
        expect(logger).to receive(:info)
        verifier = SlackVerifier.new(app)
        expect(verifier.call(env)).to include(403)
      end
    end
  end

  context 'with current time' do
    context 'and timestamp expired' do
      it 'should return 403' do
        expect(logger).to receive(:info).with(/Slack::Events::Request::TimestampExpired/)
        expect(logger).to receive(:info)
        verifier = SlackVerifier.new(app)
        expect(verifier.call(env)).to include(403)
      end
    end
  end
end
