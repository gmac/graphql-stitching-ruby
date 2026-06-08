# frozen_string_literal: true
# typed: true

require "net/http"
require "uri"
require "json"

module GraphQL
  module Stitching
    class HttpExecutable
      #: (url: String, ?headers: Hash[String, String], ?upload_types: Array[TypeName]?) -> void
      def initialize(url:, headers: {}, upload_types: nil)
        @url = url #: String
        @headers = { "Content-Type" => "application/json" }.merge!(headers) #: Hash[String, String]
        @upload_types = upload_types #: Array[TypeName]?
      end

      #: (Request request, String document, Variables variables) -> JsonMap
      def call(request, document, variables)
        form_data = extract_multipart_form(request, document, variables)

        response = if form_data
          send_multipart_form(request, form_data)
        else
          send(request, document, variables)
        end

        JSON.parse(response.body.to_s)
      end

      #: (Request _request, String document, Variables variables) -> Net::HTTPResponse
      def send(_request, document, variables)
        Net::HTTP.post(
          URI(@url),
          JSON.generate({ "query" => document, "variables" => variables }),
          @headers,
        )
      end

      #: (Request _request, MultipartForm form_data) -> Net::HTTPResponse
      def send_multipart_form(_request, form_data)
        uri = URI(@url)
        req = Net::HTTP::Post.new(uri)
        @headers.each_pair do |key, value|
          req[key] = value
        end

        req.set_form(form_data.to_a, "multipart/form-data")
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(req)
        end
      end

      # Extracts multipart upload forms per the spec:
      # https://github.com/jaydenseric/graphql-multipart-request-spec
      #: (Request request, String document, Variables variables) -> MultipartForm?
      def extract_multipart_form(request, document, variables)
        upload_types = @upload_types
        return unless upload_types && request.variable_definitions.any? && variables.any?

        files_by_path = {}

        # extract all upload scalar values mapped by their input path
        variables.each_with_object([]) do |(key, value), path|
          ast_node = request.variable_definitions[key]
          path << key
          extract_ast_node(ast_node, value, files_by_path, path, request) if ast_node
          path.pop
        end

        return if files_by_path.none?

        map = Hash.new { |h, k| h[k] = [] }
        files = files_by_path.values.tap(&:uniq!)
        variables_copy = variables.dup

        files_by_path.each_key do |path|
          orig = variables #: untyped
          copy = variables_copy #: untyped
          path.each_with_index do |key, i|
            if i == path.length - 1
              file_index = files.index(copy[key]).to_s
              map[file_index] << "variables.#{path.join(".")}"
              copy[key] = nil
            elsif orig[key].object_id == copy[key].object_id
              copy[key] = copy[key].dup
            end
            orig = orig[key]
            copy = copy[key]
          end
        end

        form = {
          "operations" => JSON.generate({
            "query" => document,
            "variables" => variables_copy,
          }),
          "map" => JSON.generate(map),
        }

        files.each_with_object(form).with_index do |(file, memo), index|
          memo[index.to_s] = file.respond_to?(:tempfile) ? file.tempfile : file
        end
      end

      private

      #: (untyped ast_node, untyped value, FilesByPath files_by_path, VariablePath path, Request request) -> void
      def extract_ast_node(ast_node, value, files_by_path, path, request)
        return unless value

        upload_types = @upload_types
        return unless upload_types

        ast_node = ast_node #: untyped
        ast_node = ast_node.of_type while ast_node.is_a?(GraphQL::Language::Nodes::NonNullType)

        if ast_node.is_a?(GraphQL::Language::Nodes::ListType)
          if value.is_a?(Array)
            value.each_with_index do |val, index|
              path << index
              extract_ast_node(ast_node.of_type, val, files_by_path, path, request)
              path.pop
            end
          end
        elsif upload_types.include?(ast_node.name)
          files_by_path[path.dup] = value
        else
          type_def = request.query.get_type(ast_node.name)
          extract_type_node(type_def, value, files_by_path, path) if type_def&.kind&.input_object?
        end
      end

      #: (untyped parent_type, untyped value, FilesByPath files_by_path, VariablePath path) -> void
      def extract_type_node(parent_type, value, files_by_path, path)
        return unless value

        upload_types = @upload_types
        return unless upload_types

        parent_type = Util.unwrap_non_null(parent_type)

        if parent_type.list?
          if value.is_a?(Array)
            value.each_with_index do |val, index|
              path << index
              extract_type_node(parent_type.of_type, val, files_by_path, path)
              path.pop
            end
          end
        elsif parent_type.kind.input_object?
          if value.is_a?(Enumerable)
            arguments = parent_type.arguments
            value.each do |key, val|
              arg_type = arguments[key]&.type
              path << key
              extract_type_node(arg_type, val, files_by_path, path) if arg_type
              path.pop
            end
          end
        elsif upload_types.include?(parent_type.graphql_name)
          files_by_path[path.dup] = value
        end
      end
    end
  end
end
