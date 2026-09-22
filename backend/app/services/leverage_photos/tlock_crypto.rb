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
  MAX_INPUT_BYTES = 48.megabytes
  NODE_HEAP_MB = 512

  def self.encrypt_bytes(bytes, locked_until)
    new.encrypt_bytes(bytes, locked_until)
  end

  def self.encrypt_outer_layer(armored_blob, locked_until)
    new.encrypt_outer_layer(armored_blob, locked_until)
  end

  def self.encrypt_attachment(attachment, locked_until, command:)
    new.encrypt_attachment(attachment, locked_until, command: command)
  end

  def self.decrypt_attachment(attachment)
    new.decrypt_attachment(attachment)
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

  def decrypt_attachment(attachment)
    raise Error, "attachment missing" unless attachment&.attached?

    attachment.open do |file|
      decrypt_from_path(file.path)
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

  def decrypt_from_path(in_path)
    raise Error, "node runner missing" unless File.exist?(RUNNER)

    Dir.mktmpdir("tlock-out-") do |dir|
      out_path = File.join(dir, "payload.bin")
      stdout, stderr, status = run_decrypt_with_retries(in_path, out_path)

      unless status&.success?
        raise_runner_failure("tlock decryption failed", stdout, stderr)
      end

      raise Error, "empty decrypted output" unless File.exist?(out_path) && File.size(out_path).positive?

      File.binread(out_path)
    end
  end

  def encrypt_from_path(command, in_path, locked_until)
    raise Error, "node runner missing" unless File.exist?(RUNNER)

    Dir.mktmpdir("tlock-out-") do |dir|
      out_path = File.join(dir, "payload.age")
      stdout, stderr, status = run_with_retries(command, in_path, out_path, locked_until_ms(locked_until))

      unless status&.success?
        raise_runner_failure("tlock encryption failed", stdout, stderr)
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
    run_node_with_retries(
      ["node", RUNNER, command, in_path, out_path, locked_until_ms.to_s],
      timeout_message: "tlock encryption timed out"
    )
  end

  def run_decrypt_with_retries(in_path, out_path)
    run_node_with_retries(
      ["node", RUNNER, "decrypt-bytes", in_path, out_path],
      timeout_message: "tlock decryption timed out"
    )
  end

  def run_node_with_retries(argv, timeout_message:)
    in_path = argv[3]
    if in_path.present? && File.exist?(in_path)
      size = File.size(in_path)
      raise Error, "tlock input too large" if size > MAX_INPUT_BYTES
    end

    attempt = 0
    begin
      attempt += 1
      stdout = stderr = status = nil
      Timeout.timeout(DEFAULT_TIMEOUT) do
        stdout, stderr, status = Open3.capture3(node_env, *argv)
      end
      [stdout, stderr, status]
    rescue Timeout::Error
      retry if attempt < MAX_ATTEMPTS
      raise Error, timeout_message
    rescue Errno::ENOENT
      raise Error, "node is not installed"
    end
  end

  def node_env
    options = ENV["NODE_OPTIONS"].to_s
    unless options.include?("max-old-space-size")
      options = [options, "--max-old-space-size=#{NODE_HEAP_MB}"].reject(&:blank?).join(" ")
    end
    ENV.to_h.merge("NODE_OPTIONS" => options)
  end

  def raise_runner_failure(prefix, stdout, stderr)
    detail = stderr.to_s.strip.presence || stdout.to_s.strip.presence || "unknown error"
    Rails.logger.error("[TlockCrypto] #{prefix}: #{detail.truncate(2000)}")
    raise Error, prefix
  end
end
