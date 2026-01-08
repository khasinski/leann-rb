# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Leann
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates LEANN database tables for storing vector indexes"

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration_file
        migration_template(
          "migration.rb.erb",
          "db/migrate/create_leann_tables.rb"
        )
      end

      def show_instructions
        say ""
        say "LEANN tables will be created!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations: rails db:migrate"
        say "  2. Configure LEANN in an initializer:"
        say ""
        say "     # config/initializers/leann.rb"
        say "     Leann.configure do |config|"
        say "       config.embedding_provider = :openai"
        say "       config.openai_api_key = ENV['OPENAI_API_KEY']"
        say "     end"
        say ""
        say "  3. Build and search indexes:"
        say ""
        say "     Leann::Rails.build('products') do"
        say "       add 'Red running shoes', category: 'shoes'"
        say "     end"
        say ""
        say "     results = Leann::Rails.search('products', 'comfortable footwear')"
        say ""
      end
    end
  end
end
