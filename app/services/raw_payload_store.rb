# Every external response is stored before it is parsed, so parser bugs can be fixed and data re-normalized
# without spending budget again (bin/rails data:renormalize).
class RawPayloadStore
  def self.capture(provider:, endpoint:, params:, status:, body:, fetched_at: Time.current)
    json = body.to_json
    RawPayload.create!(
      provider: provider, endpoint: endpoint, params_digest: Digest::SHA256.hexdigest(params.sort_by { |k, _| k.to_s }.to_json),
      fetched_at: fetched_at, status: status, body: body, body_sha256: Digest::SHA256.hexdigest(json)
    )
  end
end
