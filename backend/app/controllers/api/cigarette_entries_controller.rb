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
      value.present? && value.positive? ? value : ShowcaseController::SNAKE_SECONDS_PER_FRUIT
    end

    def apply_chaster_time(entry)
      service = ChasterService.new(current_user)
      lock = service.current_lock

      unless lock&.dig(:id).present?
        entry.chaster_error = "Aucun cadenas Chaster actif."
        return
      end

      seconds = entry.count * entry.chaster_seconds
      service.add_time_to_lock(
        lock[:id],
        seconds,
        source: "cigarettes",
        summary: "#{entry.count} cigarette(s)",
        metadata: { count: entry.count, smoked_at: entry.smoked_at&.iso8601 }
      )
      entry.chaster_lock_id = lock[:id]
      entry.chaster_applied = true
      entry.chaster_error = nil
    rescue ChasterService::Unauthorized
      entry.chaster_error = "Chaster non connecté"
    rescue ChasterService::Error => e
      entry.chaster_error = e.message.to_s.truncate(500)
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
