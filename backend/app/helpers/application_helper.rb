module ApplicationHelper
  def format_chaster_remaining(seconds)
    return t("time.finished") if seconds.nil? || seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3600
    mins = (seconds % 3600) / 60
    secs = seconds % 60

    if days.positive?
      t("time.remaining_days_hours_mins_secs", days:, hours:, mins:, secs:)
    elsif hours.positive?
      t("time.remaining_hours_mins_secs", hours:, mins:, secs:)
    elsif mins.positive?
      t("time.remaining_mins_secs", mins:, secs:)
    else
      t("time.remaining_secs", secs:)
    end
  end
end
