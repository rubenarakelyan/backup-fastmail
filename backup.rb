require "bundler/inline"
require "time"
require "yaml"

gemfile do
  source "https://rubygems.org"
  gem "thor", "~> 1.3.2"
  gem "rainbow", "~> 3.1.1"
  gem "faraday", "~> 2.12.2"
  gem "faraday-follow_redirects", "~> 0.3.0"
end

class BackupFastmail < Thor
  require "rainbow/refinement"
  using Rainbow

  desc "config", "Set configuration options"
  option :fastmail_api_token, required: true
  option :backup_directory, required: true
  def config
    yaml_config = {
      "fastmail_api_token" => options[:fastmail_api_token],
      "backup_directory" => options[:backup_directory]
    }.to_yaml

    if File.write("config.yaml", yaml_config) > 0
      puts "Config saved successfully".green
    else
      puts "Error saving config".red
    end
  end

  desc "backup-emails", "Back up Fastmail emails"
  def backup_emails
    load_and_validate_config!
    get_connection!
    version_data = load_version_data(type: "emails")
    jmap_config = get_jmap_config
    utc = Time.now.utc
    emails_from = version_data["downloaded_until"] || (utc - 604800)
    emails_to = (utc - 3600)
    emails = []

    request = {
      "using" => ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
      "methodCalls" => [
        [
          "Email/query",
          {
            "accountId" => jmap_config[:account_id],
            "sort" => [
              {
                "property": "receivedAt",
                "isAscending": false
              }
            ],
            "filter" => {
              "after" => emails_from.iso8601,
              "before" => emails_to.iso8601
            },
            "limit" => 100
          },
          "0"
        ],
        [
          "Email/get",
          {
            "accountId" => jmap_config[:account_id],
            "#ids" => {
              "name" => "Email/query",
              "path" => "/ids/*",
              "resultOf" => "0"
            },
            "properties" => %w[blobId receivedAt subject]
          },
          "1"
        ]
      ]
    }

    loop do
      response = @connection.post(jmap_config[:api_path], request.to_json)
      method_responses = JSON.parse(response.body)["methodResponses"]

      error = method_responses.map(&:first).any? do |method_response|
        method_response.downcase == "error"
      end

      if error
        puts "Error in JMAP response: #{method_responses.to_json}".red
        exit
      end

      break if method_responses.first[1]["ids"].empty?

      puts "Found #{method_responses.last[1]["list"].length} emails..."

      method_responses.last[1]["list"].each do |email|
        emails << { id: email["id"], blob_id: email["blobId"], received_at: Time.parse(email["receivedAt"]), subject: email["subject"] }
      end

      request["methodCalls"].first[1]["anchor"] = method_responses.first[1]["ids"].last
      request["methodCalls"].first[1]["anchorOffset"] = 1
    end

    puts "Backing up #{emails.length} emails..."
    puts

    emails.each_with_index do |email, index|
      if email[:received_at] == emails_to
        puts "Skipping #{email[:id]} because it's at the end of the time window".green
        puts
        next
      end

      filename = "#{email[:received_at].to_i}_#{email[:id]}.eml"
      filepath = "#{@config['backup_directory']}/#{filename}"

      if File.exist?(filepath)
        puts "Skipping #{email[:id]} because it already exists".green
        puts
        next
      end

      puts "Downloading email #{email[:id]}..."
      download_url = jmap_config[:download_url_template]
        .sub("{accountId}", jmap_config[:account_id])
        .sub("{blobId}", email[:blob_id])
        .sub("{name}", "email")
        .sub("{type}", "application/octet-stream")
      response = @connection.get(download_url)

      if response.status == 200
        File.write(filepath, response.body)
        puts "Downloaded as #{filename}".green
      else
        puts "Received unexpected HTTP status #{response.status}".red
        puts response.body
      end

      puts
      sleep (index % 100 == 0) ? 10 : 1 # try not to hit the rate limit
    end

    version_data["downloaded_until"] = emails_to
    save_version_data(type: "emails", data: version_data)

    puts "Done".green
  rescue Faraday::Error => e
    puts "Error making request: #{e.message}".red
  end

  no_commands do
    def load_and_validate_config!
      @config = YAML.safe_load_file("config.yaml")

      if @config["fastmail_api_token"].nil? || @config["fastmail_api_token"].empty?
        puts "Fastmail API token not found - run `ruby backup.rb config` to set.".red
        exit
      end

      if @config["backup_directory"].nil? || @config["backup_directory"].empty?
        puts "Backup directory not found - run `ruby backup.rb config` to set.".red
        exit
      end

      if !File.directory?(@config["backup_directory"])
        puts "Backup directory does not exist.".red
        exit
      end
    rescue Errno::ENOENT
      puts "Config file not found - run `ruby backup.rb config` to create.".red
      exit
    end

    def get_connection!
      headers = {
        "Authorization" => "Bearer #{@config["fastmail_api_token"]}",
        "Content-Type" => "application/json"
      }
      @connection ||= Faraday.new(url: "https://api.fastmail.com", headers: headers) do |faraday|
        faraday.response :follow_redirects
        faraday.options.timeout = 30
      end
    end

    def get_jmap_config
      if @connection.nil?
        puts "Connection not found".red
        exit
      end

      response = @connection.get("/.well-known/jmap")
      body = JSON.parse(response.body)

      {
        account_id: body["accounts"].keys.first,
        api_path: URI.parse(body["apiUrl"]).request_uri,
        download_url_template: body["downloadUrl"]
      }
    end

    def load_version_data(type:)
      filename = version_data_filename(type: type)

      if File.exist?(filename)
        YAML.safe_load_file(filename, permitted_classes: [Time])
      else
        {}
      end
    end

    def save_version_data(type:, data:)
      if File.write(version_data_filename(type: type), data.to_yaml) == 0
        puts "Error saving version data - everything will be downloaded again next time".red
      end
    end

    def version_data_filename(type:)
      "#{@config['backup_directory']}/#{type}.yaml"
    end
  end

  def self.exit_on_failure?
    true
  end
end

BackupFastmail.start(ARGV)
