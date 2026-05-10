# frozen_string_literal: true

module Api
  class CigaretteEntriesController < ApplicationController
    include ApiAuthenticatable

    HISTORY_DAYS = 14

    def index
      render json: tracker_payload
    end

    def create
      entry = current_user.cigarette_entries.build(
        count: count_param,
        smoked_at: smoked_at_param,
        smoked_on: smoked_at_param.to_date,
        chaster_seconds: seconds_per_cigarette
      )

      apply_chaster_time(entry)
      entry.save!

      render json: tracker_payload(latest_entry: entry), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    private

    def tracker_payload(latest_entry: nil)
      {
        today_count: count_for_date(Time.zone.today),
        today: {
          date: Time.zone.today.iso8601,
          count: count_for_date(Time.zone.today)
        },
        history: history_rows,
        seconds_per_cigarette: seconds_per_cigarette,
        entry: latest_entry && entry_to_json(latest_entry),
        latest_entry: latest_entry && entry_to_json(latest_entry)
      }
    end

    def history_rows
      entries = current_user.cigarette_entries.where(smoked_on: history_dates)
      counts = entries
        .where(smoked_on: history_dates)
        .group(:smoked_on)
        .sum(:count)
      chaster_seconds = entries
        .where(chaster_applied: true)
        .group(:smoked_on)
        .sum("count * chaster_seconds")

      history_dates.map do |date|
        {
          date: date.iso8601,
          count: counts[date] || 0,
          chaster_seconds: chaster_seconds[date] || 0
        }
      end
    end

    def history_dates
      @history_dates ||= (0...HISTORY_DAYS).map { |offset| Time.zone.today - offset.days }
    end

    def count_for_date(date)
      current_user.cigarette_entries.where(smoked_on: date).sum(:count)
    end

    def count_param
      value = params.fetch(:count, 1).to_i
      value.positive? ? value : 1
    end

    def smoked_at_param
      raw = params[:smoked_at].presence
      raw.present? ? Time.zone.parse(raw) : Time.current
    rescue ArgumentError, TypeError
      Time.current
    end

    def seconds_per_cigarette
      value = current_user.showcase_snake_seconds_per_fruit
      value.present? && value.positive? ? value : ShowcaseGameConfig::SNAKE_SECONDS_PER_FRUIT
    end

    def apply_chaster_time(entry)
      seconds = entry.count * entry.chaster_seconds
      event = BetaEvents::DomainEvent.new(
        beta: current_user,
        source: :cigarette,
        kind: :smoked_add_time,
        payload: { seconds: seconds }
      )
      execution_status = BetaEvents::ActionExecutor.new(beta: current_user, event: event).call
      if %i[source_disabled no_enabled_actions].include?(execution_status)
        entry.chaster_applied = false
        entry.chaster_lock_id = nil
        entry.chaster_error = "Source ou action désactivée."
        return
      end
      lock = ChasterService.new(current_user).current_lock
      entry.chaster_lock_id = lock&.[](:id)
      entry.chaster_applied = true
      entry.chaster_error = nil
    rescue BetaEvents::ActionExecutionStopped => e
      entry.chaster_applied = false
      entry.chaster_lock_id = nil
      entry.chaster_error = case e.reason
      when :no_chaster_lock then "Aucun cadenas Chaster actif."
      when :chaster_unauthorized then "Chaster non connecté"
      when :chaster_error, :missing_seconds then (e.detail.presence || "Erreur Chaster")
      else (e.detail.presence || "Erreur Chaster")
      end
    end

    def entry_to_json(entry)
      {
        id: entry.id,
        count: entry.count,
        smoked_on: entry.smoked_on&.iso8601,
        smoked_at: entry.smoked_at&.iso8601,
        chaster_seconds: entry.chaster_seconds,
        chaster_applied: entry.chaster_applied,
        chaster_error: entry.chaster_error
      }
    end
  end
end
