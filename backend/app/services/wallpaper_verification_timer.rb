# frozen_string_literal: true

class WallpaperVerificationTimer
  def initialize(screenshot_id)
    @screenshot_id = screenshot_id
    @steps = {}
    @started_at = monotonic_ms
  end

  def measure(step)
    step_start = monotonic_ms
    result = yield
    @steps[step] = (monotonic_ms - step_start).round
    result
  end

  def finish(status:, **attrs)
    total_ms = (monotonic_ms - @started_at).round
    log_line(status: status, action: nil, total_ms: total_ms, **attrs)
  end

  def log_action(action:, **attrs)
    total_ms = (monotonic_ms - @started_at).round
    log_line(status: nil, action: action, total_ms: total_ms, **attrs)
  end

  private

  def log_line(status:, action:, total_ms:, **attrs)
    parts = []
    parts << "action=#{action}" if action
    parts << "status=#{status}" if status
    parts << "total_ms=#{total_ms}"
    parts << "steps=#{@steps.to_json}"
    attrs.each { |key, value| parts << "#{key}=#{value}" }

    Rails.logger.info("[WallpaperVerification] screenshot=#{@screenshot_id} #{parts.join(' ')}")
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end
end
