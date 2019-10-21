require 'date'
require 'time'
require 'google_drive'
require 'sucker_punch'
require 'reporter'

class IncidentJob
  include SuckerPunch::Job
  def perform(user_id, channel_id, main_channel_id, gdrive_link, gdrive_folder_name, purpose)
    SuckerPunch.logger.info 'Starting Incident end job'
    Incident.new(SuckerPunch.logger).end user_id, channel_id, main_channel_id, gdrive_link, gdrive_folder_name, purpose
  end
end

class Incident
  attr_reader :logger

  def initialize(logger)
    @logger = logger
  end

    def get_random_string(length=7)
        source=("a".."z").to_a + (0..9).to_a
        key=""
        length.times{ key += source[rand(source.size)].to_s }
        return key
    end

    def start(user_id, main_channel_id)
        auser = $teams[user_id]['client'].users_info(user: user_id)
        buser = auser[:user][:name]

        random_channel = "incident-#{get_random_string}"

        create_channel = $teams[user_id]['client'].channels_create(
          name: random_channel,
        )

        $teams[user_id]['client'].chat_postMessage(
          channel: create_channel[:channel][:id],
          text: "Click to set purpose of incident",
            attachments: [
            {
              "blocks": [
                {
                  "type": "actions",
                  "block_id": "set_purpose",
                  "elements": [
                    {
                      "type": "button",
                      "text": {
                        "type": "plain_text",
                        "text": "Set Purpose"
                      }
                    }
                  ]
                }
              ]
            }
          ]
        )

        new_channel_id = create_channel[:channel][:id]

        $teams[user_id]['client'].chat_postMessage(
          channel: main_channel_id,
          text:   "channel named: <##{new_channel_id}> created by #{buser}"
        )

        "channel named: ##{random_channel} created"
    end

    def replace_id(text, users)
        text.split(" ").map do |word|
            word.match(/<@([A-Za-z0-9]+)>/) { |m|
                users[m[1]]
            } || word
        end.join(" ")
    end

    def end(user_id, channel_id, main_channel_id, gdrive_link, gdrive_folder_name, purpose)
      begin
        logger.info "Ending incident #{channel_id} for user #{user_id}"

        # Gets the token from config file
        session = GoogleDrive::Session.from_service_account_key("incident-slack-project.json")
        logger.info "Got GDrive session #{session}"

        logger.info 'Posting extract message'
        $teams[user_id]['client'].chat_postMessage(
          channel: channel_id,
          text:    "Ending Incident"
        )

        # get channel history
        chan_his = $teams[user_id]['client'].channels_history(
                    channel: channel_id,
                  )
        logger.debug "Got Channel history #{chan_his}"

        #get slack user ids
        chan_mem = $teams[user_id]['client'].users_list(
        )

        logger.debug "Channel members #{chan_mem}"

        users = chan_mem[:members].map do |mem|
          { mem[:id] => mem[:name] }
        end.reduce { |m, o| m.merge(o) }

        messages = chan_his[:messages].map do |message|
          {
            "date & time": Time.at(message[:ts].to_f),
            engineer: users[message[:user]],
            message: replace_id(message[:text], users)
          }
        end.sort_by {|message| message[:"date & time"]}
  
        logger.info 'Rendering report'
        summary_timeline = IncidentReport.new.render_report(messages)

        logger.info 'Uploading file'
        g_title = "#{Time.now.strftime("%Y-%m-%d-%H:%M")} - #{purpose}"
        file = session.upload_from_string(summary_timeline, "#{g_title}", convert: true, content_type: 'text/html')
        folder = session.collection_by_title("#{gdrive_folder_name}")
        folder.add(file)
        g_file_title = session.file_by_title("#{g_title}")
        g_link = g_file_title.web_view_link

        logger.info "Posting link message to #{main_channel_id}"
        $teams[user_id]['client'].chat_postMessage(
          channel: main_channel_id,
          text:    "Incident from <##{channel_id}> has been ended by <@#{user_id}> , follow the link for incident report:\n
          #{g_link}"
        )

        logger.info 'Archiving channel'
        $teams[user_id]['client'].channels_archive(
          channel: channel_id
        )
      rescue StandardError => e
        logger.error "Error during end incident: #{e.inspect}"
      end
    end
end
