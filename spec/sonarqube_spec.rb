# frozen_string_literal: true

require File.expand_path("spec_helper", __dir__)

module Danger
  describe Danger::DangerSonarqube do
    it "should be a plugin" do
      expect(Danger::DangerSonarqube.new(nil)).to be_a Danger::Plugin
    end

    SUB_ONE = %w(sub_folder/sub_one.py).freeze
    SUB_TWO = %w(sub_folder/sub_two.py).freeze
    SUB_THREE = %w(sub_folder/sub_three.py).freeze
    SUB_TWO_WARNING = "sub_two.py has less than 90.0% coverage".freeze
    PREFIX = "my_prefix_dir".freeze
    PREFIX_TWO = %w(my_prefix_dir/sub_folder/sub_two.py).freeze

    describe "with Dangerfile" do
      before do
        @dangerfile = testing_dangerfile
        @my_plugin = @dangerfile.sonarqube
        @my_plugin.task_file = "#{File.dirname(__FILE__)}/assets/report-task.txt"
        @dangerfile.git.stubs(:modified_files).returns([])
        @dangerfile.git.stubs(:added_files).returns([])
      end

      it "test" do
        #@dangerfile.git.stubs(:modified_files).returns(["Filmustage.DataApi/Filmustage.DataApi/DataAccess/Location.cs"])
        #@my_plugin.filename_prefix = "/Users/Martin/Desktop/filmustage-dataapi"
        @my_plugin.wait_for_quality_gate
      end

    end
  end
end
