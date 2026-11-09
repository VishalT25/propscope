require "rails_helper"

RSpec.describe "Registrations" do
  it "creates an account and signs in" do
    expect {
      post registration_path, params: { user: { email_address: "new@example.com", password: "password123", password_confirmation: "password123" } }
    }.to change(User, :count).by(1)
    expect(response).to redirect_to(root_url)
    expect(User.last.odds_format).to eq("american")
  end

  it "keeps a guest's decimal choice when they sign up" do
    patch preferences_path, params: { odds_format: "decimal" }
    post registration_path, params: { user: { email_address: "d@example.com", password: "password123", password_confirmation: "password123" } }
    expect(User.find_by(email_address: "d@example.com").odds_format).to eq("decimal")
  end

  it "re-renders with errors" do
    post registration_path, params: { user: { email_address: "bad", password: "short", password_confirmation: "x" } }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
