require "websocket_rails/data_store"

module WebsocketRails
  # Provides controller helper methods for developing a WebsocketRails controller. Action methods
  # defined on a WebsocketRails controller can be mapped to events using the {EventMap} class.
  #
  # == Example WebsocketRails controller
  #   class ChatController < WebsocketRails::BaseController
  #     # Can be mapped to the :client_connected event in the events.rb file.
  #     def new_user
  #       send_message :new_message, {:message => 'Welcome to the Chat Room!'}
  #     end
  #   end
  #
  # It is best to use the provided {DataStore} to temporarily persist data for each client between
  # events. Read more about it in the {DataStore} documentation.
  #
  #
  class BaseController

    # Tell Rails that BaseController and children can be reloaded when in
    # the Development environment.
    def self.inherited(controller)
      unloadable controller
    end

    # Add observers to specific events or the controller in general. This functionality is similar
    # to the Rails before_filter methods. Observers are stored as Proc objects and have access
    # to the current controller environment.
    #
    # Observing all events sent to a controller:
    #   class ChatController < WebsocketRails::BaseController
    #     observe {
    #       if data_store.each_user.count > 0
    #         puts 'a user has joined'
    #       end
    #     }
    #   end
    # Observing a single event that occurrs:
    #   observe(:new_message) {
    #     puts 'new_message has fired!'
    #   }
    def self.observe(event = nil, &block)
      if event
        @@observers[event] << block
      else
        @@observers[:general] << block
      end
    end

    # Stores the observer Procs for the current controller. See {observe} for details.
    @@observers = Hash.new {|h,k| h[k] = Array.new}

    # Provides direct access to the connection object for the client that
    # initiated the event that is currently being executed.
    def connection
      @_event.connection
    end

    # The numerical ID for the client connection that initiated the event. The ID is unique
    # for each currently active connection but can not be used to associate a client between
    # multiple connection attempts.
    def client_id
      connection.id
    end

    # The {Event} object that triggered this action.
    # Find the current event name with event.name
    # Access the data sent with the event with event.data
    # Find the event's namespace with event.namespace
    def event
      @_event
    end

    # The current message that was passed from the client when the event was initiated. The
    # message is typically a standard ruby Hash object. See the README for more information.
    def message
      @_event.data
    end
    alias_method :data, :message

    # Trigger the success callback function attached to the client event that triggered
    # this action. The object passed to this method will be passed as an argument to
    # the callback function on the client.
    def trigger_success(data=nil)
      event.success = true
      event.data = data
      event.trigger
    end

    # Trigger the failure callback function attached to the client event that triggered
    # this action. The object passed to this method will be passed as an argument to
    # the callback function on the client.
    def trigger_failure(data=nil)
      event.success = false
      event.data = data
      event.trigger
    end

    def accept_channel(data=nil)
      channel_name = event.data[:channel]
      WebsocketRails[channel_name].subscribe connection
      trigger_success data
    end

    def deny_channel(data=nil)
      trigger_failure data
    end

    # Sends a message to the client that initiated the current event being executed. Messages
    # are serialized as JSON into a two element Array where the first element is the event
    # and the second element is the message that was passed, typically a Hash.
    #
    # To send an event under a namespace, add the `:namespace => :target_namespace` option.
    #
    #   send_message :new_message, message_hash, :namespace => :product
    #
    # Nested namespaces can be passed as an array like the following:
    #
    #   send_message :new, message_hash, :namespace => [:products,:glasses]
    #
    # See the {EventMap} documentation for more on mapping namespaced actions.
    def send_message(event_name, message, options={})
      options.merge! :connection => connection, :data => message
      event = Event.new( event_name, options )
      @_dispatcher.send_message event if @_dispatcher.respond_to?(:send_message)
    end

    # Broadcasts a message to all connected clients. See {#send_message} for message passing details.
    def broadcast_message(event_name, message, options={})
      options.merge! :connection => connection, :data => message
      event = Event.new( event_name, options )
      @_dispatcher.broadcast_message event if @_dispatcher.respond_to?(:broadcast_message)
    end

    def request
      @_request
    end

    # Provides access to the {DataStore} for the current controller. The {DataStore} provides convenience
    # methods for keeping track of data associated with active connections. See it's documentation for
    # more information.
    def controller_store
      @_controller_store
    end

    def connection_store
      connection.data_store
    end

    private

    # Executes the observers that have been defined for this controller. General observers are executed
    # first and event specific observers are executed last. Each will be executed in the order that
    # they have been defined. This method is executed by the {Dispatcher}.
    def execute_observers(event)
      @@observers[:general].each do |observer|
        instance_eval( &observer )
      end
      @@observers[event].each do |observer|
        instance_eval( &observer )
      end
    end

    def delegate
      connection.controller_delegate
    end

    def method_missing(method,*args,&block)
      if delegate.respond_to? method
        delegate.send method, *args, &block
      else
        super
      end
    end

  end
end
