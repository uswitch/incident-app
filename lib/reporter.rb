# frozen_string_literal: true

require 'erb'

class IncidentReport
    def render_report(messages)
        time_format = '%Y-%m-%d %H:%M'
        ERB.new(File.read('./templates/incident-template.html.erb')).result(binding)
    end
end