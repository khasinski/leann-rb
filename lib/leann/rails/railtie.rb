# frozen_string_literal: true

module Leann
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "leann.configure_rails" do
        # Auto-configure based on Rails environment
      end

      # Expose generators
      generators do
        require "generators/leann/install/install_generator"
      end
    end
  end
end
