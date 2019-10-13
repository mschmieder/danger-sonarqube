# frozen_string_literal: true

require File.expand_path("spec_helper", __dir__)

module Danger
  describe Danger::DangerSonarqube do
    it "should be a plugin" do
      expect(Danger::DangerSonarqube.new(nil)).to be_a Danger::Plugin
    end

    describe "with Dangerfile" do
      before do
        @dangerfile = testing_dangerfile
        @my_plugin = @dangerfile.sonarqube
        @my_plugin.task_file = "#{File.dirname(__FILE__)}/assets/report-task.txt"
        @dangerfile.git.stubs(:modified_files).returns([])
        @dangerfile.git.stubs(:added_files).returns([])
      end

      it "test" do
        @my_plugin.wait_for_quality_gate
        @my_plugin.show_status
      end

    end
  end
end
