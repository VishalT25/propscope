require "rails_helper"

RSpec.describe "Authentication" do
  let(:user) { create(:user) }

  it "signs in and out" do
    post session_path, params: { email_address: user.email_address, password: "password123" }
    expect(response).to redirect_to(root_url)
    delete session_path
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects a wrong password" do
    post session_path, params: { email_address: user.email_address, password: "wrong" }
    expect(response).to redirect_to(new_session_path)
  end
end
