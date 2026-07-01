# frozen_string_literal: true

module CheckboxParamNormalizer
  module_function

  # HTML checkbox + hidden-field pairs submit duplicate values (e.g. ["0", "1"]).
  # Always take the last submitted value before casting to boolean.
  def to_bool(value)
    value = value.last if value.is_a?(Array)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
