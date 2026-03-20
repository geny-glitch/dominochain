module ApplicationHelper
  def format_chaster_remaining(seconds)
    return "Terminé" if seconds.nil? || seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3600
    mins = (seconds % 3600) / 60
    secs = seconds % 60

    if days.positive?
      "#{days}j #{hours}h #{mins}min #{secs}s"
    elsif hours.positive?
      "#{hours}h #{mins}min #{secs}s"
    elsif mins.positive?
      "#{mins}min #{secs}s"
    else
      "#{secs}s"
    end
  end
end
