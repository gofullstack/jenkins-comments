require 'spec_helper'

describe "/" do
  before :each do
    get "/"
  end

  it "returns a link to the repo" do
    last_response.body.should include "Jenkins Comments"
  end

  it "succeeds" do
    last_response.status.should == 200
  end
end
