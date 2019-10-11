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
        require 'httparty'
        require 'uri'

        attr_accessor :task_file
        attr_accessor :gate_timeout
        attr_accessor :warn_on_failure
        attr_accessor :additional_measures

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
            @warn_on_failure || False
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

            if sonar_ce_task_status == 'FAILURE'
                message = "Quality gate reported #{sonar_ce_task_status}"
                if warn_on_failure
                    warn message
                else
                    fail message
                end
            end
        end

        def show_status(*)
            status = "## Sonarqube\n".dup
            status << "### Quality Gate\n".dup
            status << quality_gate_table_header(sonar_gate_badge)
            status << table_separation

            sonar_project_analysis_quality_gate_event_description.each { |element|
                status << table_entry(element)
            }
            status << "\n"

            status << measure_table_header
            status << table_separation
            gate_status = sonar_quality_gate_project_status(sonar_project_key)
            gate_status['conditions'].each { |condition|
                if condition['status'] != 'OK'
                    status << measure_table_entry(sonar_measure_badge(condition['metricKey']),condition['status'])
                end
            }

            if additional_measures != nil
                status << "### Additional Measures\n".dup
                additional_measures.each do |measure|
                    status << sonar_measure_badge(measure) << "\n"
                end
            end

            markdown status
        end

        private
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
            analysis = sonar_project_analyses.first
            event = nil
            analysis["events"].each { |e|
                if e["category"] == 'QUALITY_GATE'
                    event = e
                    break
                end
            }
            event
        end

        def sonar_project_analysis_quality_gate_event_description
            sonar_project_analysis_quality_gate_event["description"].split(',')
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

            response.body
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

            response.body
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
