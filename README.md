# Backup Fastmail

A simple Ruby command line script that downloads eml files of all your Fastmail emails for backup purposes.

## Setup

Ensure you have the correct Ruby version and the `bundler` gem installed. All other gems will be installed automatically the first time you run the script.

## Configuration

Run `ruby backup.rb config --fastmail-api-token FASTMAIL_API_TOKEN --backup-directory BACKUP_DIRECTORY`, or copy `config.example.yaml` to `config.yaml` and edit the values.

The script uses an API token, which you can create at <https://app.fastmail.com/settings/security/tokens/new>. Select "read-only access" and the "email" scope.

The backup directory can be anywhere on your file system that you have write access to, as either an absolute or relative (from the script directory) path.
A `./backups` directory is provided as a default.

## Running backups

Run `ruby backup.rb backup-emails`. For each email, the script will download a eml file containing the full raw contents of the email including all headers.

## Errors

Most errors are captured and presented with as much information as possible.

## Acknowledgements

Thanks to Nathan Grigg for the original Python script at <https://nathangrigg.com/2021/08/fastmail-backup/>.
