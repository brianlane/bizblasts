module Public
  class BaseController < ApplicationController
    private

    def no_store!
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
      response.headers["Pragma"]        = "no-cache"
      response.headers["Expires"]       = "0"
    end
  end
end 