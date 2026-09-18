# frozen_string_literal: true

require "json"
require "open3"
require "timeout"
require "tmpdir"

class LeveragePhotos::TlockCrypto
  class Error < StandardError; end

  RUNNER = Rails.root.join("script/leverage_tlock_runner.mjs").to_s
  DEFAULT_TIMEOUT = 90
  MAX_ATTEMPTS = 2

  def self.encrypt_bytes(bytes, locked_until)
    new.encrypt_bytes(bytes, locked_until)
  end

  def self.encrypt_outer_layer(armored_blob, locked_until)
    new.encrypt_outer_layer(armored_blob, locked_until)
  end

  def self.encrypt_attachment(attachment, locked_until, command:)
    new.encrypt_attachment(attachment, locked_until, command: command)
  end

  def encrypt_bytes(bytes, locked_until)
    with_input_file(bytes.to_s) do |in_path|
      encrypt_from_path("encrypt-bytes", in_path, locked_until)
    end
  end

  def encrypt_outer_layer(armored_blob, locked_until)
    with_input_file(armored_blob.to_s) do |in_path|
      encrypt_from_path("encrypt-outer", in_path, locked_until)
    end
  end

  def encrypt_attachment(attachment, locked_until, command:)
    raise Error, "attachment missing" unless attachment&.attached?

    attachment.open do |file|
      encrypt_from_path(command, file.path, locked_until)
    end
  end

  private

  def locked_until_ms(locked_until)
    raise Error, "locked_until required" if locked_until.blank?

    time = locked_until.respond_to?(:to_time) ? locked_until.to_time : Time.zone.parse(locked_until.to_s)
    raise Error, "invalid locked_until" if time.blank? || time <= Time.current

    (time.to_f * 1000).to_i
  end

  def with_input_file(data)
    Dir.mktmpdir("tlock-in-") do |dir|
      in_path = File.join(dir, "payload.bin")
      File.binwrite(in_path, data)
      yield in_path
    end
  end

  def encrypt_from_path(command, in_path, locked_until)
    raise Error, "node runner missing" unless File.exist?(RUNNER)

    Dir.mktmpdir("tlock-out-") do |dir|
      out_path = File.join(dir, "payload.age")
      stdout, stderr, status = run_with_retries(command, in_path, out_path, locked_until_ms(locked_until))

      unless status&.success?
        detail = stderr.to_s.strip.presence || stdout.to_s.strip.presence || "unknown error"
        raise Error, "tlock encryption failed: #{detail.truncate(500)}"
      end

      armored = File.exist?(out_path) ? File.read(out_path) : ""
      data = JSON.parse(stdout.to_s)
      round = data["round"].to_i
      raise Error, "empty armored output" if armored.blank?
      raise Error, "invalid round" if round <= 0

      {
        armored: armored,
        round: round,
        chain_hash: data["chain_hash"].presence || LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      }
    end
  rescue JSON::ParserError => e
    raise Error, "invalid tlock runner output: #{e.message}"
  end

  # The node subprocess is CPU-bound and can occasionally overrun DEFAULT_TIMEOUT
  # under transient host contention (e.g. a burst of concurrent screenshot
  # comparisons). Retry once before giving up so a slow moment doesn't turn into
  # a permanently failed sanction.
  def run_with_retries(command, in_path, out_path, locked_until_ms)
    attempt = 0
    begin
      attempt += 1
      stdout = stderr = status = nil
      Timeout.timeout(DEFAULT_TIMEOUT) do
        stdout, stderr, status = Open3.capture3(
          "node", RUNNER, command, in_path, out_path, locked_until_ms.to_s
        )
      end
      [stdout, stderr, status]
    rescue Timeout::Error
      retry if attempt < MAX_ATTEMPTS
      raise Error, "tlock encryption timed out"
    rescue Errno::ENOENT
      raise Error, "node is not installed"
    end
  end
end
