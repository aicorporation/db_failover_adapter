module AiFailoverAdapter
  class Railtie < ::Rails::Railtie
    rake_tasks do
      namespace :db do
        task :load_config do
          original_config = Rails.application.config.database_configuration
          ActiveRecord::Base.configurations = AiFailoverAdapter.primary_database_configuration(original_config)
        end
      end
    end
  end
end