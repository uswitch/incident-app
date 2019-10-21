# Incident-app for slack

The aim of the slackbot `incident-app` is to simplify the way incidents are managed. `incident-app` will create a new channel for the incident, once the incident has been resolved then the chat history of that channel will be exported into a google drive incident report template.


## Prerequisite

**Note** : `<app-url>` is link to your app-server whether it is somewhere in cloud or URL provided by [ngrok](https://ngrok.com/) if testing locally

* Read about [Slack API documentation](https://api.slack.com/#read_the_docs) & [here](https://api.slack.com/start) about creation of slack apps

* Once app is created on slack, You can see your app here: `https://api.slack.com/apps`, go to your app

* Go to `Interactive Components`, Add Request URL as `https://<app-url>/actions`

* Go to Slash Commands, Add `/incident-test` (or command of your choice) & set Request URL to `https://<app-url>/incident`

* Go to OAuth & Permissions, Set `Redirect URLs` to `https://<app-url>/finish_auth`

* Follow this [guide](https://github.com/gimite/google-drive-ruby/blob/master/doc/authorization.md#on-behalf-of-no-existing-users-service-account) & create Service Account in Google account to give programmatic access of Google Drive to out incident-app

* Save keys in a json file as `incident-slack-project.json`

* You can use/edit the existing incident-template.html.erb file in the `templates` folder to generate the google doc

# Try it Out

* ### Locally

    - ##### Setting Environment variables
        - Set timezone
            ```
            export TZ='Europe/London'
            ```
        - Go to your App's `Basic information` page for following secrets

            ```
            export SLACK_CLIENT_ID="XXXX.XXXX"
            export SLACK_API_SECRET="XXXX"
            export SLACK_SIGNING_SECRET="XXXX"
            export SLACK_REDIRECT_URI="<app-url>/finish_auth"
            export SLACK_BEGIN_AUTH_URI="<app-url>/begin_auth"
            export SLACK_CHANNEL_ID=xxxxxx // This will be main channel 
            ```

        - Set Google Drive Specific variables

             ```
             export GDRIVE_FOLDER_ID=https://drive.google.com/drive/folders/xxxxxx &&
             export GDRIVE_FOLDER_NAME=incident-folder-staging
             ```
             
        - Set link to document about Severity levels

            ```
            export SEVERITY_HELP_URL=<link>
            ```

    * Install [Bundler](http://bundler.io/) as below:

        ```
        gem install bundler:2.0.2
        ```

    * run following to get the gems needed

        ```
        bundle install
        ```

    * You will need a server that can recieve HTTPS traffic from slack. You can use [ngrok](https://ngrok.com/), Our app uses `9292` port, expose this port using ngrok and keep this terminal open

        ```
        ngrok http 9292
        ```

    * Run the App

        ```
        bundle exec rackup --host 0.0.0.0 -p 9292
        ```
* ### On Kubernetes
    
    * You can use manifests from [k8s](./k8s/) directory to deploy this app on kubernetes
    * Create secret from `incident-slack-project.json` file

        ```
        kubectl create secret generic incident-slack-project --from-file=incident-slack-project.json
        ```
    * Create secret,

        ```
        kubectl create secret generic incident-app --from-literal=api_secret=$SLACK_API_SECRET --from-literal=client_id=$SLACK_CLIENT_ID --from-literal=signing_secret=$SLACK_SIGNING_SECRET
        ```

## Usage

* `/incident-test` or `/incident-test help` will show help

* `/incident-test start` will create a new channel on your behalf to start managing the incident. If this is the first time you're using the app or your token has expired then you will be asked to authenticate in a browser

* `/incident-test end` will create a google doc of the chat history & put it in google drive and also archive the channel on your behalf.


## :tada: Star, Fork, Contribute :tada:
