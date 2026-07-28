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

  it "retries once after a transient timeout before succeeding" do
    locked_until = 1.hour.from_now
    call_count = 0
    allow(Open3).to receive(:capture3) do
      call_count += 1
      raise Timeout::Error if call_count == 1

      ['{"armored":"-----BEGIN AGE ENCRYPTED FILE-----\nok\n-----END AGE ENCRYPTED FILE-----","round":1,"chain_hash":"abc"}', "", instance_double(Process::Status, success?: true)]
    end
    allow(Timeout).to receive(:timeout).and_yield

    result = described_class.encrypt_bytes("hello-photo", locked_until)

    expect(call_count).to eq(2)
    expect(result[:round]).to eq(1)
  end

  it "raises after exhausting all retry attempts" do
    locked_until = 1.hour.from_now
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

    expect do
      described_class.encrypt_bytes("hello-photo", locked_until)
    end.to raise_error(described_class::Error, /timed out/)
  end
end
