require "ai_failover_adapter/version"

module AiFailoverAdapter
  class << self

    # Get the connection adapter class for an adapter name. The class will be loaded from
    # ActiveRecord::ConnectionAdapters::NameAdapter where Name is the camelized version of the name.
    # If the adapter class does not fit this pattern (i.e. sqlite3 => SQLite3Adapter), then add
    # the mapping to the +ADAPTER_TO_CLASS_NAME_MAP+ Hash.
    def adapter_class_for(name)
      name = name.to_s
      class_name = ADAPTER_TO_CLASS_NAME_MAP[name] || name.camelize
      "ActiveRecord::ConnectionAdapters::#{class_name}Adapter".constantize
    end

  end
end
