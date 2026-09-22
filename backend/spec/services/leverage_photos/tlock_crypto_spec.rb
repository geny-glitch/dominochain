# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::TlockCrypto do
  it "encrypts bytes into an armored age payload", :aggregate_failures do
    skip "node is not available" unless system("node", "-v", out: File::NULL, err: File::NULL)

    locked_until = 1.hour.from_now
    result = described_class.encrypt_bytes("hello-photo", locked_until)

    expect(result[:armored]).to include("-----BEGIN AGE ENCRYPTED FILE-----")
    expect(result[:round]).to be > 0
    expect(result[:chain_hash]).to be_present
  end

  it "wraps an armored payload without sending it through JSON stdin" do
    skip "node is not available" unless system("node", "-v", out: File::NULL, err: File::NULL)

    inner = described_class.encrypt_bytes("hello-photo", 1.hour.from_now)
    outer = described_class.encrypt_outer_layer(inner[:armored], 2.hours.from_now)

    expect(outer[:armored]).to include("-----BEGIN AGE ENCRYPTED FILE-----")
    expect(outer[:round]).to be > inner[:round]
  end

  it "retries once after a transient timeout before succeeding" do
    locked_until = 1.hour.from_now
    call_count = 0
    allow(Open3).to receive(:capture3) do |*_args|
      out_path = _args[-2]
      call_count += 1
      raise Timeout::Error if call_count == 1

      File.write(out_path, "-----BEGIN AGE ENCRYPTED FILE-----\nok\n-----END AGE ENCRYPTED FILE-----")
      ['{"round":1,"chain_hash":"abc"}', "", instance_double(Process::Status, success?: true)]
    end
    allow(Timeout).to receive(:timeout).and_yield

    result = described_class.encrypt_bytes("hello-photo", locked_until)

    expect(call_count).to eq(2)
    expect(result[:round]).to eq(1)
    expect(result[:armored]).to include("BEGIN AGE")
  end

  it "does not leak node heap dumps in the raised error" do
    locked_until = 1.hour.from_now
    dump = "<--- Last few GCs ---> FATAL ERROR: JavaScript heap out of memory"
    allow(Open3).to receive(:capture3).and_return(
      ["", dump, instance_double(Process::Status, success?: false)]
    )
    allow(Timeout).to receive(:timeout).and_yield

    expect do
      described_class.encrypt_bytes("hello-photo", locked_until)
    end.to raise_error(described_class::Error, "tlock encryption failed")
  end

  it "raises after exhausting all retry attempts" do
    locked_until = 1.hour.from_now
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

    expect do
      described_class.encrypt_bytes("hello-photo", locked_until)
    end.to raise_error(described_class::Error, /timed out/)
  end
end
