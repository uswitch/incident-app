# frozen_string_literal: true

require 'sucker_punch'
require 'sinatra/base'
require 'slack-ruby-client'
require 'slack_verifier'
require 'json'
require 'incident'

ENV['TZ'] = 'Europe/London'

# This class contains all of the webserver logic for processing incoming
# requests from Slack.
class API < Sinatra::Base
  use SlackVerifier

  slack_begin_auth_uri = ENV['SLACK_BEGIN_AUTH_URI']
  main_channel_id = ENV['SLACK_CHANNEL_ID']
  gdrive_link = ENV['GDRIVE_FOLDER_ID']
  gdrive_folder_name = ENV['GDRIVE_FOLDER_NAME']
  VALID_START_EXPRESSION = /start/
  VALID_END_EXPRESSION = /end/
  HELP_RESPONSE = 'Use `/incident` to start or end an incident. Example: `/incident start or /incident end`'.freeze
  INVALID_RESPONSE = 'Sorry, I didn’t quite get that. Try `/incident start or /incident end`'.freeze

  configure do
    enable :logging
    set :logging, Logger::INFO
  end

  post '/incident' do
    logger.debug JSON.pretty_generate(env)

    channel_id = params['channel_id'].to_s.strip
    user_id = params['user_id'].to_s.strip
    # extract data from slack payload
    case params['text'].to_s.strip
      when 'help', '' then HELP_RESPONSE

      when VALID_START_EXPRESSION then
        logger.info 'Start incident called'

        unless $teams[user_id]
          logger.info "#{user_id} needs authentication"
          return "Please authenticate first: #{slack_begin_auth_uri}?a=start"
        end

        logger.info 'Starting new incident'

        incident = Incident.new(logger)
        incident.start(user_id, main_channel_id)

      when VALID_END_EXPRESSION then
        logger.info "End incident called by #{user_id}"
        unless $teams[user_id]
          logger.info "#{user_id} needs authentication"
          return "Please authenticate first: #{slack_begin_auth_uri}?a=end&channel_id=#{channel_id}"
        end

        logger.info 'Ending incident'
        IncidentJob.perform_async(user_id, channel_id, main_channel_id, gdrive_link, gdrive_folder_name, @@purpose)
      else INVALID_RESPONSE
    end
  end

  post '/actions' do
    logger.info 'Actions called'
    request_data = JSON.parse params['payload']

    incident_channel_id = request_data['channel']['id']
    incident_user_id = request_data['user']['id']
    if request_data['type'] == "dialog_submission"
      @@purpose = request_data['submission']['purpose']
      logger.info 'Setting Channel Purpose'
      $teams[incident_user_id]['client'].channels_setPurpose(
        channel: incident_channel_id,
        purpose: @@purpose,
      )
      username = request_data['user']['name']
      chan_info_txt = "<##{incident_channel_id}> with Purpose '#{@@purpose}' set by #{username}"
      $teams[incident_user_id]['client'].chat_postMessage(
        channel: main_channel_id,
        text: chan_info_txt
      )

      help_url = ENV['SEVERITY_HELP_URL']

      $teams[incident_user_id]['client'].chat_postMessage(
        channel: incident_channel_id,
        text:   "Please select the severity.",
        attachments: [
          {
            "blocks": [
              {
                "type": "actions",
                "block_id": "severity_block",
                "elements": [
                  {
                    "type": "button",
                    "text": {
                      "type": "plain_text",
                      "text": "TBC"
                    }
                  },
                  {
                    "type": "button",
                    "text": {
                      "type": "plain_text",
                      "text": "1. High"
                    }
                  },
                  {
                    "type": "button",
                    "text": {
                      "type": "plain_text",
                      "text": "2. Medium"
                    }
                  },
                  {
                    "type": "button",
                    "text": {
                      "type": "plain_text",
                      "text": "3. Low"
                    }
                  }
                ]
              },
              {
                "type": "section",
                "text": {
                  "type": "mrkdwn",
                  "text": "Click on the button to learn about Severity Levels"
                },
                "accessory": {
                  "type": "button",
                  "text": {
                    "type": "plain_text",
                    "text": "the button",
                    "emoji": true
                  },
                  "url": help_url
                }
              }
            ]
          }
        ]
      )
    elsif request_data['actions'][0]['block_id'] == "set_purpose"
       trigger_id = request_data['trigger_id']
       # MODAL FOR setting purpose
       $teams[incident_user_id]['client'].dialog_open(
         trigger_id: trigger_id,
         "dialog": {
           "callback_id": "ryde-46e2b0",
           "title": "Purpose of Incident",
           "submit_label": "Update",
           "notify_on_cancel": true,
           "state": "Limo",
           "elements": [
               {
                   "type": "text",
                   "label": "Purpose",
                   "name": "purpose",
                   "placeholder": "What's the issue?"
               }
           ]
         }
       )

    else
      severity = request_data['actions'][0]['text']['text']
      if severity != 'the button'
        logger.info 'Setting Channel Topic'
        $teams[incident_user_id]['client'].channels_setTopic(
          channel: incident_channel_id,
          topic: severity,
        )
        username = request_data['user']['username']
        # Severity Posting to Main Channel
        chan_info_txt = "<##{incident_channel_id}> with severity level '#{severity}' set by #{username}"
        logger.info 'Posting information to main channel'
        $teams[incident_user_id]['client'].chat_postMessage(
          channel: main_channel_id,
          text: chan_info_txt
        )
      end
    end
    logger.info 'Done with action'
  end
end
