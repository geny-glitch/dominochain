# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaEvents::ActionExecutor do
  let(:beta) { create(:user, :beta) }
  let(:event) do
    BetaEvents::DomainEvent.new(
      beta: beta,
      source: :cigarette,
      kind: :smoked_add_time,
      payload: { seconds: 120 }
    )
  end

  let(:action_instance) { instance_double(BetaEvents::Actions::ChasterAddTimeFromEvent, call: true) }

  before do
    allow(BetaEvents::ConsequenceRegistry).to receive(:actions_for).with(event).and_return([ BetaEvents::Actions::ChasterAddTimeFromEvent ])
    allow(BetaEvents::Actions::ChasterAddTimeFromEvent).to receive(:new).and_return(action_instance)
  end

  it "returns source_disabled and does not execute actions when source is hidden in catalog" do
    beta.update!(beta_ui_prefs: { "catalog_visibility" => { "sources" => { "cigarettes" => false } } })

    result = described_class.new(beta: beta, event: event).call

    expect(result).to eq(:source_disabled)
    expect(action_instance).not_to have_received(:call)
  end

  it "returns no_enabled_actions when all mapped actions are disabled" do
    beta.update!(beta_ui_prefs: { "catalog_visibility" => { "actions" => { "chaster" => false } } })

    result = described_class.new(beta: beta, event: event).call

    expect(result).to eq(:no_enabled_actions)
    expect(action_instance).not_to have_received(:call)
  end

  it "executes actions when source and action are enabled" do
    result = described_class.new(beta: beta, event: event).call

    expect(result).to eq(:ok)
    expect(action_instance).to have_received(:call).once
  end
end
