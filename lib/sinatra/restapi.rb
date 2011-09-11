require 'json'

# ## Sinatra::RestAPI [module]
# A plugin for providing rest API to models. Great for Backbone.js.
#
# To use this, simply `register` it to your Sinatra Application.  You can then
# use `rest_create` and `rest_resource` to create your routes.
#
#     class App < Sinatra::Base
#       register Sinatra::RestAPI
#     end
#
#
# ### JSON conversion
#
# The *create* and *get* routes all need to return objects as JSON. RestAPI
# attempts to convert your model instances to JSON by first trying
# `object.to_json` on it, then trying `object.to_hash.to_json`.
#
# It's recommended you implement `#to_hash` in your models.
#
module Sinatra::RestAPI
  def self.registered(app)
    app.helpers Helpers
  end

  # ### rest_create(path, &block) [method]
  # Creates a *create* route on the given `path`.
  #
  # This creates a `POST` route in */documents* that accepts JSON data.
  # This route will return the created object as JSON.
  #
  # When getting a request, it does the following:
  # 
  #  * A new object is created by *yielding* the block you give. (Let's
  #    call it `object`.)
  #
  #  * For each of the attributes, it uses the `attrib_name=` method in
  #    your record. For instance, for an attrib like `title`, it wil lbe
  #    calling `object.title = "hello"`.
  #
  #  * `object.save` will be called.
  #
  #  * `object`'s contents will then be returned to the client as JSON.
  #
  # See the example.
  #
  #     class App < Sinatra::Base
  #       rest_create "/documents" do
  #         Document.new
  #       end
  #     end
  #
  def rest_create(path, options={}, &blk)
    # Create
    post path do
      @object = yield
      rest_params.each { |k, v| @object.send :"#{k}=", v }
      @object.save
      rest_respond @object.to_hash
    end
  end

  # ### rest_resource(path, &block) [method]
  # Creates a *get*, *edit* and *delete* route on the given `path`.
  #
  # The block given will be yielded to do a record lookup. If the block returns
  # `nil`, RestAPI will return a *404*.
  #  
  # If you are using Backbone, ensure that you are *not* setting
  # `Backbone.emulateHTTP` to `true`.
  #
  # In the example, it creates routes for `/document/:id` to accept HTTP *GET*
  # (for object retrieval), *PUT* (for editing), and *DELETE* (for destroying).
  #
  # Your model needs to implement the following methods:
  #
  #    * `save` (called on edit)
  #    * `destroy` (called on delete)
  #    * `<attrib_name_here>=` (called for each of the attributes on edit)
  #
  # See the example.
  #
  #     class App < Sinatra::Base
  #       rest_resource "/document/:id" do
  #         Document.find(id)
  #       end
  #     end
  #
  def rest_resource(path, options={}, &blk)
    before path do |id|
      @object = yield(id) or pass
    end

    # Get
    get path do |id|
      rest_respond @object
    end

    # Edit
    put path do |id|
      rest_params.each { |k, v| @object.send :"#{k}=", v  unless k == 'id' }
      @object.save
      rest_respond @object
    end

    # Delete
    delete path do |id|
      @object.destroy
      rest_respond :result => :success
    end
  end

  # ### Helper methods
  # There are some helper methods that are used internally be `RestAPI`,
  # but you can use them too if you need them.
  #
  module Helpers
    # ### Helper: rest_respond(object) [helper]
    # Responds with a request with the given `object`.
    #
    # This will convert that object to either JSON or XML as needed, depending
    # on the client's preferred type (dictated by the HTTP *Accepts* header).
    #
    def rest_respond(obj)
      case request.preferred_type('*/json', '*/xml')
      when '*/json'
        content_type :json
        rest_convert obj, :to_json

      when '*/xml'
        content_type :xml
        rest_convert obj, :to_xml

      else
        pass
      end
    end

    # ### Helper: rest_params [helper]
    # Returns the object from the request.
    #
    # If the client sent `application/json` (or `text/json`) as the content
    # type, it tries to parse the request body as JSON.
    #
    # If the client sent a standard URL-encoded POST with a `model` key
    # (happens when Backbone uses `Backbone.emulateJSON = true`), it tries
    # to parse it's key as JSON.
    #
    # Otherwise, the params will be returned as is.
    #
    def rest_params
      if File.fnmatch('*/json', request.content_type)
        JSON.parse request.body.read

      elsif params['model']
        # Account for Backbone.emulateJSON.
        JSON.parse params['model']

      else
        params
      end
    end

    def rest_convert(obj, method)
      if obj.respond_to?(method)
        obj.send method
      elsif obj.respond_to?(:to_hash)
        obj.to_hash.send method
      else
        raise "Can't convert object #{method}"
      end
    end
  end
end
