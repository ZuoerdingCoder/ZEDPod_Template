require 'fileutils'
require 'colored2'

module Pod
    class TemplateConfigurator
        
        attr_reader :pod_name, :pods_for_podfile, :prefixes, :test_example_file, :username, :email, :http_url, :ssl_url, :home_page_url,:framework
        
        def initialize(pod_name)
            @pod_name = pod_name
            @pods_for_podfile = []
            @prefixes = []
            @message_bank = MessageBank.new(self)
        end
        
        def ask(question)
            answer = ""
            loop do
                puts "\n#{question}?"
                
                @message_bank.show_prompt
                answer = gets.chomp
                
                break if answer.length > 0
                
                print "\nYou need to provide an answer."
            end
            answer
        end
        
        def ask_with_answers(question, possible_answers)
            
            print "\n#{question}? ["
            
            print_info = Proc.new {
                
                possible_answers_string = possible_answers.each_with_index do |answer, i|
                    _answer = (i == 0) ? answer.underlined : answer
                    print " " + _answer
                    print(" /") if i != possible_answers.length-1
                end
                print " ]\n"
            }
            print_info.call
            
            answer = ""
            
            loop do
                @message_bank.show_prompt
                answer = gets.downcase.chomp
                
                answer = "yes" if answer == "y"
                answer = "no" if answer == "n"
                
                # default to first answer
                if answer == ""
                    answer = possible_answers[0].downcase
                    print answer.yellow
                end
                
                break if possible_answers.map { |a| a.downcase }.include? answer
                
                print "\nPossible answers are ["
                print_info.call
            end
            
            answer
        end
        
        def run
            @message_bank.welcome_message
            
            @framework = self.ask_with_answers("What language do you want to use?", ["Swift", "ObjC"]).to_sym
            case @framework
                when :swift
                ConfigureSwift.perform(configurator: self)
                
                when :objc
                ConfigureIOS.perform(configurator: self)
            end
            
            enter_git_info
            replace_variables_in_files
            clean_template_files
            rename_template_files
            add_pods_to_podfile
            customise_prefix
            rename_classes_folder
            ensure_carthage_compatibility
            reinitialize_git_repo
            run_pod_install
            
            @message_bank.farewell_message
        end
        
        #----------------------------------------#
        
        def ensure_carthage_compatibility
            FileUtils.ln_s('Example/Pods/Pods.xcodeproj', '_Pods.xcodeproj')
        end
        
        def run_pod_install
            puts "\nRunning " + "pod install".magenta + " on your new library."
            puts ""
            
            Dir.chdir("Example") do
                system "pod install"
            end
            
            `git add Example/#{pod_name}.xcodeproj/project.pbxproj`
            `git commit -m "Initial commit"`
        end
        
        def clean_template_files
            ["./**/.gitkeep", "configure", "_CONFIGURE.rb", "README.md", "LICENSE", "templates", "setup", "CODE_OF_CONDUCT.md"].each do |asset|
                `rm -rf #{asset}`
            end
        end
        
        def enter_git_info
#            http_url = nil
#            ssl_url = nil
#            page_url = nil

            loop do
                @http_url = self.ask("Enter HTTPS Repo URL")
                
                if @http_url.include?(' ')
                    puts 'Your class HTTPS Repo URL cannot contain spaces.'.red
                    else
                    break
                end
            end

            loop do
                @ssl_url = self.ask("Enter SSH Repo URL")
                
                if @ssl_url.include?(' ')
                    puts 'Your class SSH Repo URL cannot contain spaces.'.red
                    else
                    break
                end
            end

            loop do
                @home_page_url = self.ask("Enter Home Page URL")

                if @home_page_url.include?(' ')
                    puts 'Your class Home Page cannot contain spaces.'.red
                    else
                    break
                end
            end

        end
        
        
        def replace_variables_in_files
            file_names = ['POD_LICENSE', 'POD_README.md', 'NAME.podspec', '.travis.yml', podfile_path,fastfile_path,'upload.sh']
            file_names.each do |file_name|
                text = File.read(file_name)
                text.gsub!("${POD_NAME}", @pod_name)
                text.gsub!("${REPO_NAME}", @pod_name.gsub('+', '-'))
                text.gsub!("${USER_NAME}", user_name)
                text.gsub!("${USER_EMAIL}", user_email)
                text.gsub!("${YEAR}", year)
                text.gsub!("${DATE}", date)
                text.gsub!("${HOME_PAGE_URL}", @home_page_url)
                text.gsub!("${HTTPS_REPO_URL}", @http_url)
                File.open(file_name, "w") { |file| file.puts text }
            end
        end
        
        def add_pod_to_podfile podname
            @pods_for_podfile << podname
        end
        
        def add_pods_to_podfile
            podfile = File.read podfile_path
            podfile_content = @pods_for_podfile.map do |pod|
                "pod '" + pod + "'"
            end.join("\n  ")
            podfile.gsub!("${INCLUDED_PODS}", podfile_content)
            File.open(podfile_path, "w") { |file| file.puts podfile }
        end
        
        def add_line_to_pch line
            @prefixes << line
        end
        
        def customise_prefix
            prefix_path = "Example/Tests/Tests-Prefix.pch"
            return unless File.exists? prefix_path
            
            pch = File.read prefix_path
            pch.gsub!("${INCLUDED_PREFIXES}", @prefixes.join("\n  ") )
            File.open(prefix_path, "w") { |file| file.puts pch }
        end
        
        
        def set_test_framework(test_type, extension)
            content_path = "setup/test_examples/" + test_type + "." + extension
            folder = extension == "m" ? "ios" : "swift"
            tests_path = "templates/" + folder + "/Example/Tests/Tests." + extension
            tests = File.read tests_path
            tests.gsub!("${TEST_EXAMPLE}", File.read(content_path) )
            File.open(tests_path, "w") { |file| file.puts tests }
        end
        
        def rename_template_files
            FileUtils.mv "POD_README.md", "README.md"
            FileUtils.mv "POD_LICENSE", "LICENSE"
            FileUtils.mv "NAME.podspec", "#{pod_name}.podspec"
        end
        
        def rename_classes_folder
            FileUtils.mv "Pod", @pod_name
        end
        
        def reinitialize_git_repo
            `rm -rf .git`
            `git init`
            `git add -A`
            `git remote add origin "#{ssl_url}"`
            
        end
        
        def validate_user_details
            return (user_email.length > 0) && (user_name.length > 0)
        end
        
        #----------------------------------------#
        
        def user_name
            (`git config user.name` || ENV['GIT_COMMITTER_NAME'] || github_user_name ||  `<GITHUB_USERNAME>` ).strip
        end
        
        def github_user_name
            github_user_name = `security find-internet-password -s github.com | grep acct | sed 's/"acct"<blob>="//g' | sed 's/"//g'`.strip
            is_valid = github_user_name.empty? or github_user_name.include? '@'
            return is_valid ? nil : github_user_name
        end
        
        def user_email
            (ENV['GIT_COMMITTER_EMAIL'] || `git config user.email`).strip
        end
        
        def year
            Time.now.year.to_s
        end
        
        def date
            Time.now.strftime "%m/%d/%Y"
        end
        
        def podfile_path
            'Example/Podfile'
        end
        
        def fastfile_path
            'Example/fastlane/Fastfile'
        end
        
        #----------------------------------------#
    end
end
