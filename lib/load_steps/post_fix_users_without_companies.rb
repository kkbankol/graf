require 'load_steps/load_step'
require 'octokit_utils'
require 'log_level'
require 'constants'

class PostFixUsersWithoutCompanies < LoadStep
  def name
    "Fix Users Without Companies"
  end

  def execute(*args)
    puts "Start Step: #{name}"

    GithubLoad.log_current_msg("***Fixing Users Without Companies", LogLevel::INFO)
    client = OctokitUtils.get_octokit_client

    # For each company
   Constants.get_org_to_company_mapping.each { |mapping|
      company = Company.find_by(name: mapping['company'])

      # For each org which maps to this company
      mapping['orgs'].each { |org_name|

        orgMembers = client.organization_members(org_name)
        orgMembers.each { |member|
          user = User.find_by(login: member[:attrs][:login])

          # Only put in a company if they don't already have one
          if user && (!user.company || user.company == Company.find_by(name: "Independent"))
            GithubLoad.log_current_msg("#{user} is in #{company}", LogLevel::INFO)
            user.company = company
            user.save
          end
        }
      }
    }

    puts "Finish Step: #{name}"
  end

  def revert
  
  end
end