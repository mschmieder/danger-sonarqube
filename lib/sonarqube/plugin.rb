module Danger
    # Show code coverage of modified and added files.
    # Add warnings if minimum file coverage is not achieved.
    #
    # @example Warn on minimum file coverage of 30% and show all modified files coverage.
    #       cobertura.report = "path/to/my/report.xml"
    #       cobertura.warn_if_file_less_than(percentage: 30)
    #       cobertura.show_coverage
    #
    # @see  mschmieder/danger-sonarqube
    # @tags sonarqube, static-analysis
    #
    class DangerSonarqube < Plugin
        require 'inifile'
        require 'fileutils'
        require 'httparty'
        require 'uri'

        attr_accessor :task_file
        attr_accessor :gate_timeout
        attr_accessor :warn_on_failure
        attr_accessor :additional_measures
        attr_accessor :image_dir

        ERROR_FILE_NOT_SET = "Sonarqube task file not set. Use 'sonarqube.file = \"path/to/my/report-task.txt\"'.".freeze
        ERROR_FILE_NOT_FOUND = "No file found at %s".freeze
        HTTP_ERROR = "HTTP error %s: %s".freeze
        TIMEOUT_ERROR = "Sonarqube gate did not finish within %s seconds. Set 'gate_timeout' to increase timeout if necessary".freeze
        TABLE_COLUMN_LINE = "-----".freeze

        # API ENDPOINTS
        GATE_BADGES_ENPOINT = '/api/badges/gate'
        MEASURE_BADGES_ENPOINT = '/api/badges/measure'
        PROJECT_ANALYISIS_SEARCH_ENDPINT = '/api/project_analyses/search'
        QUALITY_GATE_PROJECT_STATUS_ENDPOINT = '/api/qualitygates/project_status'

        # attribute to set the path to the sonar report-task file
        #
        # @return [String] path to task file.
        def task_file
            @task_file || ".sonar/report-task.txt"
        end

        # attribute to set the gate timeout
        #
        # @return [Integer] time in seconds
        def gate_timeout
            @gate_timeout || 360
        end

        # Instead of failing just warn on a gate failure
        #
        # @return [Boolean] true or false
        def warn_on_failure
            @warn_on_failure || false
        end

        # Location where the badges will be stored
        #
        # @return [String] path to directory
        def image_dir
            @image_dir || ".danger/sonarqube/"
        end

        # This function will wait
        #
        # @return [String] task status.
        def wait_for_quality_gate
            # wait until the quality gate reports back
            timeout = 0
            sleep_time = 10
            while timeout < gate_timeout do
                break if sonar_ce_task_status == 'SUCCESS' || sonar_ce_task_status == 'FAILURE'
                sleep sleep_time
                timeout += sleep_time
            end

            # check if timout was reached
            raise format(TIMEOUT_ERROR, gate_timeout) unless timeout < gate_timeout

            if sonar_quality_gate_project_status(sonar_project_key)['status'] != 'OK'
                message = "Quality gate reported #{sonar_quality_gate_project_status(sonar_project_key)['status']}"
                if warn_on_failure
                    warn message
                else
                    fail message
                end
            end
        end

        def show_status(*)
            status = "## Sonarqube\n".dup
            if sonar_quality_gate_project_status(sonar_project_key)['status'] == 'OK'
                status << markdown_image(sonar_gate_badge,"Quality Gate")
                status << "\n"
            else
                if sonar_project_analysis_quality_gate_event_description != nil
                    status << quality_gate_table_header(markdown_image(sonar_gate_badge, "Quality Gate"))
                    status << table_separation
                    sonar_project_analysis_quality_gate_event_description.each { |element|
                        status << table_entry(element)
                    }
                end
                status << "\n"

                measure = measure_table_header
                measure << table_separation
                measure_entries = ""
                gate_status = sonar_quality_gate_project_status(sonar_project_key)
                gate_status['conditions'].each { |condition|
                    if condition['status'] != 'OK'
                        measure_entries << measure_table_entry(sonar_measure_badge(condition['metricKey']), condition['status'])
                    end
                }

                if measure_entries != ""
                    status << measure
                    status << measure_entries
                end
            end

            if additional_measures != nil
                status << "### Additional Measures\n".dup
                additional_measures.each do |measure|
                    status << markdown_image(sonar_measure_badge(measure), measure) << "\n"
                end
            end

            markdown status
        end

        private

        # URL to the current project
        #
        # @return [String] url to the current project.
        def ci_project_url
            url = nil
            if defined? @dangerfile.gitlab
                url = ENV['CI_PROJECT_URL']
            else
                raise "This plugin does not yet support github or bitbucket, would love PRs: https://github.com/mschmieder/danger-sonarqube/"
            end
            url
        end

        # ID of the current CI job
        #
        # @return [String] ci job id
        def ci_job_id
            id = nil
            if defined? @dangerfile.gitlab
                id = ENV['CI_JOB_ID']
            else
                raise "This plugin does not yet support github or bitbucket, would love PRs: https://github.com/mschmieder/danger-sonarqube/"
            end
            id
        end

        def parse_task_file
            raise ERROR_FILE_NOT_SET if task_file.nil? || task_file.empty?
            raise format(ERROR_FILE_NOT_FOUND, task_file) unless File.exist?(task_file)

            IniFile.load(task_file)
        end

        # Queries for the current ce task
        #
        # @return [String] task status.
        def sonar_ce_task
            response = HTTParty.get(basic_auth(sonar_ce_task_url))
            raise format(HTTP_ERROR, response.code, response.body) unless response.ok?
            JSON.parse(response.body)['task']
        end

        # Retrieves the ce task status
        #
        # @return [String] task status.
        def sonar_ce_task_status
            sonar_ce_task['status']
        end

        # Retrieves the sonar auth token from the environment
        #
        # @return [String] Auth token.
        def sonar_auth_token
            ENV['SONAR_AUTH_TOKEN']
        end

        # Convenient method to not always parse the task file but keep it in the memory.
        #
        # @return [IniFile::Hash] The task report object.
        def sonar_task_report
            @sonar_task_report ||= parse_task_file
        end

        # Retrieves the project key from the ini file
        #
        # @return [String] The project key url.
        def sonar_project_key
            sonar_task_report['global']['projectKey']
        end

        # Retrieves the server url from the ini file
        #
        # @return [String] The server url.
        def sonar_server_url
            sonar_task_report['global']['serverUrl']
        end

        # Retrieves the ce task id from the ini file
        #
        # @return [String] The ce task id.
        def sonar_ce_task_id
            sonar_task_report['global']['ceTaskId']
        end

        # Retrieves the task url from the ini file
        #
        # @return [String] The ce task url.
        def sonar_ce_task_url
            sonar_task_report['global']['ceTaskUrl']
        end

        # Retrieves the last analysis made on the project
        #
        # @return [Hash] structure containing all data about the event
        def sonar_project_analyses
            query = {
                "project"  => sonar_project_key,
                "category" => "QUALITY_GATE",
                "ps"       => 1
            }
            url = basic_auth("#{sonar_server_url}/#{PROJECT_ANALYISIS_SEARCH_ENDPINT}")
            response = HTTParty.get(url,
                :query => query
            )
            raise format(HTTP_ERROR, response.code, response.body) unless response.ok?
            JSON.parse(response.body)["analyses"]
        end

        # Retrieves the quality gate event
        #
        # @return [Hash] structure containing all data about the event
        def sonar_project_analysis_quality_gate_event
            event = nil
            if !sonar_project_analyses.empty?
                analysis = sonar_project_analyses.first
                if analysis.key?("events")
                    analysis["events"].each { |e|
                        if e["category"] == 'QUALITY_GATE'
                            event = e
                            break
                        end
                    }
                end
            end
            event
        end

        def sonar_project_analysis_quality_gate_event_description
            sonar_project_analysis_quality_gate_event["description"].split(',') unless sonar_project_analysis_quality_gate_event == nil
        end

        # Retrieves the svg badge for the quality gate
        #
        # @return [String] raw svg string
        def sonar_gate_badge
            query = {
                "key"      => sonar_project_key,
                "blinking" => "false",
                "template" => "ROUNDED"
            }
            url = basic_auth("#{sonar_server_url}/#{GATE_BADGES_ENPOINT}")

            response = HTTParty.get(url,
                :query => query
            )
            raise format(HTTP_ERROR, response.code, response.body) unless response.ok?

            save_badge(response.body, "quality_gate")
        end

        # Markdwon representation of image
        #
        # @return [String] markdown an image
        def markdown_image(url, text)
            "![#{text}](#{url})"
        end

        # Retrieves the svg badge for a given metric
        #
        # @param metric metric id to use
        # @return [String] raw svg string
        def sonar_measure_badge(metric)
            query = {
                "key"      => sonar_project_key,
                "blinking" => "false",
                "template" => "ROUNDED",
                "metric"   => metric
            }
            url = basic_auth("#{sonar_server_url}/#{MEASURE_BADGES_ENPOINT}")

            response = HTTParty.get(url,
                :query => query
            )
            raise format(HTTP_ERROR, response.code, response.body) unless response.ok?

            save_badge(response.body, metric)
        end

        # Will save the badge locally and compute the url
        # where it can be retrieved
        #
        # @param metric metric id to use
        # @return [String] url to retrieve the badge
        def save_badge(badge, metric)
            # make sure directory exists
            dirname = File.dirname(image_dir)
            unless File.directory?(image_dir)
              FileUtils.mkdir_p(image_dir)
            end

            # wirte file
            File.write("#{image_dir}/#{metric}.svg", badge)

            # compute url
            url = "#{ci_project_url}/-/jobs/#{ci_job_id}/artifacts/file/#{image_dir}/#{metric}.svg"
        end

        # Retrieves the Quality Gate Project Status
        #
        # @param projectKey project key to search for
        # @return [Hash] structure containing project status
        def sonar_quality_gate_project_status(projectKey)
            query = {
                "projectKey" => projectKey
            }
            url = basic_auth("#{sonar_server_url}/#{QUALITY_GATE_PROJECT_STATUS_ENDPOINT}")

            response = HTTParty.get(url,
                :query => query
            )
            raise format(HTTP_ERROR, response.code, response.body) unless response.ok?
            JSON.parse(response.body)['projectStatus']
        end

        # Adds basic auth user to url
        #
        # @param url url that needs to be augmented with basic auth
        # @return [String] basic auth url.
        def basic_auth(url)
            uri = URI.parse(url)
            if sonar_auth_token
                uri.user=sonar_auth_token
            end
            uri.to_s
        end

        # Create the table_entry table rows.
        #
        # @param item item to put information in the table row.
        # @return [String] Markdown for table rows.
        def table_entry(item)
            line = "||#{item}"
            line << "\n"
        end

        # Create the measure_table_entry column headers.
        #
        # @return [String] Markdown for table headers.
        def measure_table_entry(badge, item)
            line = "|#{badge}|#{item}"
            line << "\n"
        end

        # Create the quality_gate_table_header column headers.
        #
        # @return [String] Markdown for table headers.
        def quality_gate_table_header(badge)
            line = "|#{badge}|Information".dup
            line << "\n"
        end

        # Create the table header separation line.
        #
        # @return [String] Markdown for table headers.
        def measure_table_header
            line = "|Measure|Status".dup
            line << "\n"
        end

        # Create the table header separation line.
        #
        # @return [String] Markdown for table header separation.
        def table_separation
            line = "|#{TABLE_COLUMN_LINE}|#{TABLE_COLUMN_LINE}".dup
            line << "\n"
        end
    end
end
