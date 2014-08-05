require File.join(File.dirname(__FILE__), 'active_record', 'connection_adapters', 'ai_failover_adapter.rb')
require File.join(File.dirname(__FILE__), 'ai_failover_adapter', 'railtie.rb') if defined?(Rails::Railtie)
require "ai_failover_adapter/version"

module AiFailoverAdapter
  class << self

    ADAPTER_TO_CLASS_NAME_MAP = {"sqlite" => "SQLite", "sqlite3" => "SQLite3", "postgresql" => "PostgreSQL", 'mssql' => 'MSSQL'}

    # Get the connection adapter class for an adapter name. The class will be loaded from
    # ActiveRecord::ConnectionAdapters::NameAdapter where Name is the camelized version of the name.
    # If the adapter class does not fit this pattern (i.e. sqlite3 => SQLite3Adapter), then add
    # the mapping to the +ADAPTER_TO_CLASS_NAME_MAP+ Hash.
    def adapter_class_for(name)
      name = name.to_s
      class_name = ADAPTER_TO_CLASS_NAME_MAP[name] || name.camelize
      "ActiveRecord::ConnectionAdapters::#{class_name}Adapter".constantize
    end

    def primary_database_configuration(configs)
      configs.each do |key, values|
        if values['adapter'] == 'ai_failover'
          values['adapter'] = values.delete('node_adapter')
          if values['hosts']
            values['host'] = values['hosts'][0]
            values.delete('hosts')
          else
            values['url'] = values['urls'][0]
            values.delete('urls')
          end
        end
        configs[key] = values
      end

      configs
    end

  end
end
