# frozen_string_literal: true

module BetaEvents
  # Applies each active SanctionSet item as a separate DomainEvent through ActionExecutor.
  class SanctionApplier
    DEFAULT_KIND_MAP = {
      "chaster.add_time" => :chaster_add_time,
      "chaster.freeze" => :chaster_freeze,
      "pishock.shock" => :pishock,
      "leverage_photo.lock" => :leverage_photo_lock,
      "leverage_photo.delete" => :leverage_photo_delete
    }.freeze

    def initialize(beta:, source:, kind_map: {}, execute: nil)
      @beta = beta
      @source = source.to_sym
      @kind_map = kind_map.transform_keys(&:to_s)
      @execute = execute
    end

    def apply!(sanction_set, metadata: {}, hooks: {}, config_overrides: {})
      results = []
      sanction_set.active_items.each do |item|
        next if skip_item?(item, hooks)

        kind = resolve_kind(item.possibility_id)
        config = item.config.dup
        override = config_overrides[item.possibility_id] || {}
        if override[:seconds_multiplier].to_i > 1
          config[:seconds] = config[:seconds].to_i * override[:seconds_multiplier].to_i
        end
        override.each do |key, value|
          next if key == :seconds_multiplier

          config[key] = value
        end

        hooks[:before]&.call(item)

        payload = build_payload(item.possibility_id, config, metadata, kind)
        event = DomainEvent.new(
          beta: @beta,
          source: @source,
          kind: kind,
          payload: payload
        )
        context = Context.new(beta: @beta, event: event)
        result = execute_event(event, context)

        hooks[:after]&.call(item, result, context)

        results << {
          "kind" => kind.to_s,
          "action" => ActionRegistry.legacy_action_for(item.possibility_id) || item.possibility_id,
          "possibility_id" => item.possibility_id,
          "result" => result,
          "applied_at" => Time.current.iso8601,
          **metadata_for(item.possibility_id, config, context)
        }
      end
      results
    end

    private

    def skip_item?(item, hooks)
      return true if item.possibility_id == "chaster.freeze" && hooks[:skip_freeze]&.call

      false
    end

    def resolve_kind(possibility_id)
      @kind_map[possibility_id] || DEFAULT_KIND_MAP[possibility_id] || possibility_id.tr(".", "_").to_sym
    end

    def build_payload(possibility_id, config, metadata, kind)
      meta = metadata.dup
      meta["enforcement_kind"] = kind.to_s if @source == :wallpaper

      payload = {
        possibility_id: possibility_id,
        action: ActionRegistry.legacy_action_for(possibility_id),
        source: @source.to_s,
        metadata: meta
      }
      case possibility_id
      when "chaster.add_time"
        payload[:seconds] = config[:seconds]
      when "pishock.shock"
        payload[:pishock_intensity] = config[:intensity]
        payload[:pishock_duration] = config[:duration]
        payload[:intensity] = config[:intensity]
        payload[:duration] = config[:duration]
      when "leverage_photo.lock"
        payload[:seconds] = config[:seconds]
        payload[:target_mode] = config[:target_mode].presence || "random"
        payload[:photo_id] = config[:photo_id] if config[:photo_id].present?
      when "leverage_photo.delete"
        payload[:target_mode] = config[:target_mode].presence || "random"
        payload[:photo_id] = config[:photo_id] if config[:photo_id].present?
      end
      payload
    end

    def metadata_for(possibility_id, config, context)
      case possibility_id
      when "chaster.add_time"
        { "chaster_seconds" => config[:seconds] }
      when "pishock.shock"
        {
          "pishock_intensity" => config[:intensity],
          "pishock_duration" => config[:duration]
        }
      when "leverage_photo.lock", "leverage_photo.delete"
        meta = {
          "target_mode" => config[:target_mode],
          "leverage_photo_id" => context.leverage_photo_id || config[:photo_id]
        }
        meta["seconds"] = config[:seconds] if config[:seconds].present?
        meta
      else
        {}
      end
    end

    def execute_event(event, context)
      if @execute
        @execute.call(event, context)
      else
        ActionExecutor.new(beta: @beta, event: event, context: context).call_safe
      end
    end
  end
end
