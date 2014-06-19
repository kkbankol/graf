class ApplicationController < ActionController::Base
  protect_from_forgery
  # TODO: Need to add back in
  #force_ssl
  before_filter :require_login

  private

  def require_login
    unless current_user
      redirect_to login_url
    end
  end

  def current_user
    @current_user ||= GrafUser.find(session[:user_id]) if session[:user_id]
  end

  helper_method :current_user
end
