module ActiveRecord
  module ConnectionHandling

    #
    # Active record will call this method to 
    # establish a connection. This will in
    # turn create multiple connections to the
    # different databases supplied by the
    # configuration
    #
    # @param config The database configuration
    #
    def ai_failover_connection(config)
      config = config.with_indifferent_access
      default_config = config.merge(adapter: config[:node_adapter]).with_indifferent_access
      default_config.delete(:hosts)
      default_config.delete(:urls)
      default_config.delete(:node_adapter)

      establish_adapter(default_config[:adapter])
      db_destinations = (config[:urls] || config[:hosts])
      db_conn_key = config[:urls] ? :url : :host

      db_connections = []
      db_destinations.each do |dest|
        conn_config = {}
        conn_config[db_conn_key] = dest
        db_config = default_config.merge(conn_config)

        begin
          establish_adapter(db_config[:adapter])
          conn = send("#{db_config[:adapter]}_connection".to_sym, db_config)
          db_connections << conn
        rescue StandardError => e
          if logger
            logger.error("Error connecting to database #{db_config.inspect}")
            logger.error(e)
          end
        end
      end

      if db_connections.length == 0
        raise 'Unable to connect to any of the specified databases'
      elsif db_connections.length < db_destinations.length
        logger.warn("Unable to connect to all specified databases. Conntected to #{db_connections.length}")
      end

      klass = ::ActiveRecord::ConnectionAdapters::AiFailoverAdapter.adapter_class(db_connections.first)
      klass.new(nil, logger, db_connections)

    end

    #
    # This method ensures the actual adapter
    # that is needed is loaded.
    #
    def establish_adapter(adapter)
      raise AdapterNotSpecified.new('Database configuration does not specify adapter') unless adapter
      raise AdapterNotFound.new('Database configuration must specify adapters. Do not use ai_failover_adapter') if adapter == 'ai_failover_adapter'

      if defined?(JRuby)
        ar_adapter = "jdbc#{adapter}"
      end

      begin
        require 'rubygems'
        gem "activerecord-#{ar_adapter}-adapter"
        require "active_record/connection_adapters/#{ar_adapter}_adapter"
      rescue LoadError
        begin
          require "active_record/connection_adapters/#{ar_adapter}_adapter"
        rescue LoadError
          raise "Please install the #{ar_adapter}: `gem install activerecord-#{ar_adapter}-adapter` (#{$!})"
        end
      end

      adapter_method = "#{adapter}_connection"
      if !respond_to?(adapter_method)
        raise AdapterNotFound, "Database configuration specifies nonexistent #{adapter} adapter"
      end

    end

  end

  module ConnectionAdapters
    class AiFailoverAdapter < AbstractAdapter

      attr_reader :available_connections
      attr_reader :current_connection

      class << self

        def adapter_class(connection)
          adapter_class_name = connection.adapter_name.classify
          return const_get(adapter_class_name) if const_defined?(adapter_class_name, false)

          connection_methods = []
          override_classes = (connection.class.ancestors - AbstractAdapter.ancestors)
          override_classes.each do |connection_class|
            connection_methods.concat(connection_class.public_instance_methods(false))
            connection_methods.concat(connection_class.protected_instance_methods(false))
          end
          connection_methods = connection_methods.collect { |m| m.to_sym }.uniq
          connection_methods -= public_instance_methods(false) + protected_instance_methods(false) + private_instance_methods(false)

          klass = Class.new(self)
          connection_methods.each do |method_name|
            klass.class_eval <<-EOS, __FILE__, __LINE__ + 1
              def #{method_name}(*args, &block)
                connection = current_connection
                return proxy_connection_method(connection, :#{method_name}, *args, &block)
              end
            EOS
          end

          const_set(adapter_class_name, klass)

          return klass
        end

        def visitor_for(pool)
          # This is ugly, but then again, so is the code in ActiveRecord for setting the arel
          # visitor. There is a note in the code indicating the method signatures should be updated.
          config = pool.spec.config.with_indifferent_access
          adapter = config[:node_adapter]
          AiFailoverAdapter.adapter_class_for(adapter).visitor_for(pool)
        end

      end

      def initialize(connection, logger, available_connections)
        @all_connections = available_connections.dup.freeze
        @available_connections = available_connections.each_with_index.map { |conn, idx| AvailableConnection.new(conn, idx) }
        super(connection, logger)
      end

      # TODO: Think about supering this so we can append "AIFailover"
      # Removed so we report the underlying adapter type for SQL compatibility.
      # def adapter_name
      #   'Ai_Failover_Adapter'
      # end

      def all_connections
        @all_connections
      end

      def current_connection
        available_connections.first.try(:connection)
      end

      def requires_reloading?
        false
      end

      def visitor=(visitor)
        @all_connections.each { |conn| conn.visitor = visitor }
      end

      def visitor
        current_connection.visitor
      end

      def active?
        active = true
        do_to_connections { |conn| active &= conn.active? }
        active
      end

      def reconnect!
        do_to_connections { |conn| conn.reconnect! }
      end

      def disconnect!
        do_to_connections { |conn| conn.disconnect! }
      end

      def reset!
        do_to_connections { |conn| conn.reset! }
      end

      def verify!(*ignored)
        do_to_connections { |conn| conn.verify!(*ignored) }
      end

      def reset_runtime
        total = 0.0
        do_to_connections { |conn| total += conn.reset_runtime }
        total
      end

      def to_s
        "#<#{self.class.name}:0x#{object_id.to_s(16)} #{all_connections.size} connections>"
      end

      def inspect
        to_s
      end

      private

      def active_and_available?(connection)
        # If it's not active, return false
        return false unless connection.active?
        # TODO - Check if the database is setup to go into maintenance mode
        return true
      end

      def available_connections
        available = @available_connections
        connections = []
        available.each do |conn|
          if conn.active?
            connections << conn
          else
            if conn.expired?
              reconnect_in_background(conn)
            end
          end
        end

        # Now that that's done, only return active connections, and in
        # order of priority. This way the highest priority connections
        # will always get used when available. Priority is simply
        # determined by the order in which they are added to the 
        # configuration
        active = connections.map { |ac| ac if ac.active? }.flatten
        active.sort_by { |ac| ac.priority }
      end

      def do_to_connections
        @available_connections.each do |conn|
          begin
            yield(conn) if conn.active
          rescue => e
          end
        end
      end

      def reset_connections
        @available_connections.each do |conn|
          unless conn.connection.active?
            conn.connection.reconnect! rescue nil
          end
        end
      end

      def ignore_connection(connection, expires)
        available = available_connections
        connections = available.reject { |c| c == connection }

        # There are no connections left. Whoops. Retry them
        if connections.empty?
          @logger.warn("All connections are marked dead - trying them all again") if @logger
          reset_connections
        else
          # Remove this connection for the required amount of time
          # and also push it to the bottom of the list
          @logger.warn("Removing #{connection.inspect} from the connection pool for #{expires} seconds") if @logger
          available_connection = @available_connections.delete_at(@available_connections.index { |c| c.connection == connection })
          available_connection.active = false
          available_connection.expires = 30.seconds.from_now
          @available_connections.push(available_connection)
        end
      end

      def reconnect_in_background(available_connection)
        unless available_connection.is_reconnecting?
          Thread.new {
            begin
              @logger.info("Attempting to add dead database back to connection pool") if @logger
              available_connection.reconnect!
            rescue => e
              @logger.warn("Failed to reconnect to database when adding connect back to the pool")
              @logger.warn(e)

              available_connection.expires = 30.seconds.from_now
              available_connection.active = false
            end
          }
        end
      end

      def proxy_connection_method(connection, method, *args, &block)
        unless connection.blank?
          begin
            connection.send(method, *args, &block)
          rescue => e
            if active_and_available?(connection)
              # Normal error occurred, raise it
              raise e
            else
              ignore_connection(connection, 30)
              proxy_connection_method(current_connection, method, *args, &block)
            end
          end
        else
          raise "Unable to find an active connection"
        end
      end

      class DatabaseConnectionError < StandardError
      end

      class AvailableConnection
        attr_reader :connection, :priority
        attr_writer :expires, :active
        attr_reader :reconnecting

        def initialize(connection, priority)
          @priority = priority
          @connection = connection
          @active = true
        end

        def active?
          @active
        end

        def expired?
          @expires ? @expires <= Time.now : false
        end

        def is_reconnecting?
          @reconnecting
        end

        def reconnect!
          @reconnecting = true
          @connection.reconnect!
          
          unless @connection.active?
            @active = false
            @reconnecting = false
            raise DatabaseConnectionError.new
          end

          @expires = nil
          @active = true
          @reconnecting = false
        end

      end

    end
  end

end