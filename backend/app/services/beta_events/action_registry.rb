# frozen_string_literal: true

module BetaEvents
  # Declarative catalog of action possibilities (executable variants + config schema).
  # Sources bind events to these possibilities; they do not invent new action types.
  class ActionRegistry
    Possibility = Struct.new(
      :id,
      :catalog_id,
      :executor,
      :config_schema,
      keyword_init: true
    ) do
      def config_fields
        config_schema || {}
      end
    end

    LEGACY_ACTION_TO_POSSIBILITY = {
      "chaster_add_time" => "chaster.add_time",
      "chaster_freeze" => "chaster.freeze",
      "pishock" => "pishock.shock",
      "leverage_photo_lock" => "leverage_photo.lock",
      "leverage_photo_start" => "leverage_photo.lock",
      "leverage_photo_add_time" => "leverage_photo.lock",
      "leverage_photo_delete" => "leverage_photo.delete"
    }.freeze

    POSSIBILITY_TO_LEGACY_ACTION = {
      "chaster.add_time" => "chaster_add_time",
      "chaster.freeze" => "chaster_freeze",
      "pishock.shock" => "pishock",
      "leverage_photo.lock" => "leverage_photo_lock",
      "leverage_photo.delete" => "leverage_photo_delete"
    }.freeze

    class << self
      def all
        @all ||= build_all.freeze
      end

      def find(possibility_id)
        all[possibility_id.to_s]
      end

      def for_catalog(catalog_id)
        all.values.select { |p| p.catalog_id == catalog_id.to_s }
      end

      def executor_for(possibility_id)
        find(possibility_id)&.executor
      end

      def catalog_id_for_executor(executor_class)
        key = executor_class.to_s
        all.values.find { |p| p.executor.to_s == key }&.catalog_id
      end

      def possibility_id_for_legacy_action(action)
        LEGACY_ACTION_TO_POSSIBILITY[action.to_s]
      end

      def legacy_action_for(possibility_id)
        POSSIBILITY_TO_LEGACY_ACTION[possibility_id.to_s]
      end

      def normalize_config(possibility_id, raw)
        possibility = find(possibility_id)
        return {} unless possibility

        hash = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
        result = {}

        possibility.config_fields.each do |key, schema|
          key_s = key.to_s
          value = hash[key_s]
          value = hash[key.to_s] if value.nil?
          value = hash[key.to_sym] if value.nil? && hash.key?(key.to_sym)

          if value.nil? || value == ""
            result[key.to_sym] = schema[:default] if schema.key?(:default)
            next
          end

          result[key.to_sym] = normalize_field(value, schema)
        end

        result
      end

      def resolve_binding_config(binding, event)
        binding = binding.deep_symbolize_keys
        config = {}

        if binding[:config].is_a?(Hash)
          config.merge!(binding[:config].deep_symbolize_keys)
        end

        if binding[:config_resolver].present?
          resolved = ConfigResolvers.resolve(binding[:config_resolver], event)
          return nil if resolved.nil?

          config.merge!(resolved.deep_symbolize_keys)
        end

        if binding[:rate_limit].present?
          config[:rate_limit] = binding[:rate_limit].deep_symbolize_keys
        end

        normalize_config(binding[:possibility_id], config)
      end

      private

      def build_all
        defs = [
          {
            id: "chaster.add_time",
            catalog_id: "chaster",
            executor: Actions::ChasterAddTimeFromEvent,
            config_schema: {
              seconds: { type: :integer, min: 1, max: 86_400 * 365, required: true, ui: :number },
              rate_limit: { type: :object, optional: true, ui: :hidden }
            }
          },
          {
            id: "chaster.freeze",
            catalog_id: "chaster",
            executor: Actions::ChasterFreezeFromEvent,
            config_schema: {}
          },
          {
            id: "chaster.unfreeze",
            catalog_id: "chaster",
            executor: Actions::ChasterUnfreezeFromEvent,
            config_schema: {}
          },
          {
            id: "pishock.shock",
            catalog_id: "pishock",
            executor: Actions::EnqueuePishockFromEvent,
            config_schema: {
              intensity: { type: :integer, min: 1, max: 100, default: 50, ui: :number },
              duration: { type: :integer, min: 1, max: 15, default: 1, ui: :number }
            }
          },
          {
            id: "leverage_photo.lock",
            catalog_id: "leverage_photo",
            executor: Actions::LeveragePhotoLockFromEvent,
            config_schema: {
              seconds: {
                type: :integer,
                min: LeveragePhoto::MIN_DURATION_SECONDS,
                max: LeveragePhoto::MAX_DURATION_SECONDS,
                required: true,
                ui: :number
              },
              target_mode: { type: :enum, values: %w[random specific], default: "random", ui: :leverage_target },
              photo_id: { type: :integer, optional: true, ui: :leverage_photo_id }
            }
          },
          {
            id: "leverage_photo.delete",
            catalog_id: "leverage_photo",
            executor: Actions::LeveragePhotoDeleteFromEvent,
            config_schema: {
              target_mode: { type: :enum, values: %w[random specific], default: "random", ui: :leverage_target },
              photo_id: { type: :integer, optional: true, ui: :leverage_photo_id }
            }
          }
        ]

        defs.each_with_object({}) do |definition, memo|
          possibility = Possibility.new(**definition)
          memo[possibility.id] = possibility
        end
      end

      def normalize_field(value, schema)
        case schema[:type]
        when :integer
          n = value.to_i
          n = [ n, schema[:min] ].max if schema[:min]
          n = [ n, schema[:max] ].min if schema[:max]
          n
        when :enum
          s = value.to_s
          schema[:values].include?(s) ? s : schema[:default]
        when :object
          value.is_a?(Hash) ? value.deep_symbolize_keys : {}
        else
          value
        end
      end
    end
  end
end
