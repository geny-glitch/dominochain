# frozen_string_literal: true

# Runs on staging via fly ssh. Prints one base64 line to stdout.
# Usage: bin/rails runner script/download_staging_blob.rb BLOB_KEY

require "base64"

key = ARGV.fetch(0)
blob = ActiveStorage::Blob.find_by!(key: key)
puts "B64_START"
print Base64.strict_encode64(blob.download)
puts
puts "B64_END"
