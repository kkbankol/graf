require 'github_loader'
require 'log_level'
require 'db_utils'

class LoadController < ApplicationController
  
  def load_status
    # Check to see what the status of the load is
    #load_id = params[:load]
    load_id = GithubLoad.last.id
    #load = GithubLoad.find(load_id)
    load = GithubLoad.last # TODO, Debate this, Shouldn't we continue on from last load since we're only using a single DB? 
    last_msg_id = params[:last_msg]

    # Get messages since we last checked
    messages = GithubLoadMsg.getMsgs(load_id, last_msg_id)

    # Populate completed field based on load
    completed = load.load_complete_time ? 'true' : 'false'
    
    # Send back the JSON object
   
    render :json => "{\"completed\": \"#{completed}\", \"messages\": #{GithubLoadMsg.message_array_to_json_formatted(messages)}}"
  end

  def start_load
    # Create the load object
    load = GithubLoader.prep_github_load

    # Spawn new thread to do the actual load
    Thread.new do
      GithubLoader.github_load(load)

      # Close thread's DB connection
      ActiveRecord::Base.connection.close
    end

    render :text => "#{load.id}"
  end

  def index
    @github_loads = GithubLoad.all

    # Is there a running load?
    @running_load = nil
    last_load = @github_loads.last
    if last_load && last_load.load_complete_time == nil
      @running_load = last_load
      @running_msgs = GithubLoadMsg.getMsgs(@running_load.id)
    end

    @error_log_level = LogLevel::ERROR
  end

  def delete_load_history
    GithubLoad.delete_all
    GithubLoadMsg.delete_all

    render :text => "Load History Deleted"
  end

  def delete_all_data
    DBUtils.delete_all_data
    render :text => "All Data Deleted"
  end
  
end
