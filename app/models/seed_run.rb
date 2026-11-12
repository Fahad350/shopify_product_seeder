# One click of "Seed Store": overall status, counts, and a result row per product.
class SeedRun < ApplicationRecord
  STATUSES = %w[running completed completed_with_errors failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  # result: { "source_id", "title", "outcome" (created|updated|skipped|failed), "shopify_id", "messages" }
  def add_result(result)
    results << result.stringify_keys
    counter = "#{result[:outcome]}_count"
    self[counter] += 1 if has_attribute?(counter)
  end

  def finish!(error: nil)
    self.error_message = error
    self.status = if error then "failed"
                  elsif failed_count.positive? then "completed_with_errors"
                  else "completed"
                  end
    self.finished_at = Time.current
    save!
  end
end
