# frozen_string_literal: true

module SearchEngineIndexingSupport
  extend ActiveSupport::Concern

  included do
    before_action :apply_search_engine_indexing_headers
    helper_method :page_indexable?, :search_engine_noindex?
  end

  def page_indexable?
    SearchEngineIndexing.page_indexable?(controller_name: controller_name, action_name: action_name)
  end

  def search_engine_noindex?
    SearchEngineIndexing.noindex?(controller_name: controller_name, action_name: action_name)
  end

  private

  def apply_search_engine_indexing_headers
    return unless search_engine_noindex?

    response.headers["X-Robots-Tag"] = SearchEngineIndexing::NOINDEX_DIRECTIVE
  end
end
