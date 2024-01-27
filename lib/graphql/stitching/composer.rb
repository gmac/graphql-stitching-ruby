# frozen_string_literal: true

require_relative "./composer/base_validator"
require_relative "./composer/validate_interfaces"
require_relative "./composer/validate_boundaries"

module GraphQL
  module Stitching
    class Composer
      class ComposerError < StitchingError; end
      class ValidationError < ComposerError; end

      # @api private
      NO_DEFAULT_VALUE = begin
        class T < GraphQL::Schema::Object
          field(:f, String) do
            argument(:a, String)
          end
        end

        T.get_field("f").get_argument("a").default_value
      end

      # @api private
      BASIC_VALUE_MERGER = ->(values_by_location, _info) { values_by_location.values.find { !_1.nil? } }

      # @api private
      BASIC_ROOT_FIELD_LOCATION_SELECTOR = ->(locations, _info) { locations.last }

      # @api private
      VALIDATORS = [
        "ValidateInterfaces",
        "ValidateBoundaries",
      ].freeze

      # @return [String] name of the Query type in the composed schema.
      attr_reader :query_name

      # @return [String] name of the Mutation type in the composed schema.
      attr_reader :mutation_name

      # @api private
      attr_reader :candidate_types_by_name_and_location

      # @api private
      attr_reader :schema_directives

      def initialize(
        query_name: "Query",
        mutation_name: "Mutation",
        description_merger: nil,
        deprecation_merger: nil,
        default_value_merger: nil,
        directive_kwarg_merger: nil,
        root_field_location_selector: nil
      )
        @query_name = query_name
        @mutation_name = mutation_name
        @description_merger = description_merger || BASIC_VALUE_MERGER
        @deprecation_merger = deprecation_merger || BASIC_VALUE_MERGER
        @default_value_merger = default_value_merger || BASIC_VALUE_MERGER
        @directive_kwarg_merger = directive_kwarg_merger || BASIC_VALUE_MERGER
        @root_field_location_selector = root_field_location_selector || BASIC_ROOT_FIELD_LOCATION_SELECTOR
        @stitch_directives = {}

        @field_map = nil
        @boundary_map = nil
        @mapped_type_names = nil
        @candidate_directives_by_name_and_location = nil
        @schema_directives = nil
      end

      def perform(locations_input)
        reset!
        schemas, executables = prepare_locations_input(locations_input)

        # "directive_name" => "location" => candidate_directive
        @candidate_directives_by_name_and_location = schemas.each_with_object({}) do |(location, schema), memo|
          (schema.directives.keys - schema.default_directives.keys - GraphQL::Stitching.stitching_directive_names).each do |directive_name|
            memo[directive_name] ||= {}
            memo[directive_name][location] = schema.directives[directive_name]
          end
        end

        # "directive_name" => merged_directive
        @schema_directives = @candidate_directives_by_name_and_location.each_with_object({}) do |(directive_name, directives_by_location), memo|
          memo[directive_name] = build_directive(directive_name, directives_by_location)
        end

        @schema_directives.merge!(GraphQL::Schema.default_directives)

        # "Typename" => "location" => candidate_type
        @candidate_types_by_name_and_location = schemas.each_with_object({}) do |(location, schema), memo|
          raise ComposerError, "Location keys must be strings" unless location.is_a?(String)
          raise ComposerError, "The subscription operation is not supported." if schema.subscription

          introspection_types = schema.introspection_system.types.keys
          schema.types.each do |type_name, type_candidate|
            next if introspection_types.include?(type_name)

            if type_name == @query_name && type_candidate != schema.query
              raise ComposerError, "Query name \"#{@query_name}\" is used by non-query type in #{location} schema."
            elsif type_name == @mutation_name && type_candidate != schema.mutation
              raise ComposerError, "Mutation name \"#{@mutation_name}\" is used by non-mutation type in #{location} schema."
            end

            type_name = @query_name if type_candidate == schema.query
            type_name = @mutation_name if type_candidate == schema.mutation
            @mapped_type_names[type_candidate.graphql_name] = type_name if type_candidate.graphql_name != type_name

            memo[type_name] ||= {}
            memo[type_name][location] = type_candidate
          end
        end

        enum_usage = build_enum_usage_map(schemas.values)

        # "Typename" => merged_type
        schema_types = @candidate_types_by_name_and_location.each_with_object({}) do |(type_name, types_by_location), memo|
          kinds = types_by_location.values.map { _1.kind.name }.tap(&:uniq!)

          if kinds.length > 1
            raise ComposerError, "Cannot merge different kinds for `#{type_name}`. Found: #{kinds.join(", ")}."
          end

          extract_boundaries(type_name, types_by_location) if type_name == @query_name

          memo[type_name] = case kinds.first
          when "SCALAR"
            build_scalar_type(type_name, types_by_location)
          when "ENUM"
            build_enum_type(type_name, types_by_location, enum_usage)
          when "OBJECT"
            build_object_type(type_name, types_by_location)
          when "INTERFACE"
            build_interface_type(type_name, types_by_location)
          when "UNION"
            build_union_type(type_name, types_by_location)
          when "INPUT_OBJECT"
            build_input_object_type(type_name, types_by_location)
          else
            raise ComposerError, "Unexpected kind encountered for `#{type_name}`. Found: #{kinds.first}."
          end
        end

        builder = self
        schema = Class.new(GraphQL::Schema) do
          orphan_types schema_types.values
          query schema_types[builder.query_name]
          mutation schema_types[builder.mutation_name]
          directives builder.schema_directives.values

          own_orphan_types.clear
        end

        select_root_field_locations(schema)
        expand_abstract_boundaries(schema)

        supergraph = Supergraph.new(
          schema: schema,
          fields: @field_map,
          boundaries: @boundary_map,
          executables: executables,
        )

        VALIDATORS.each do |validator|
          klass = Object.const_get("GraphQL::Stitching::Composer::#{validator}")
          klass.new.perform(supergraph, self)
        end

        supergraph
      end

      # @!scope class
      # @!visibility private
      def prepare_locations_input(locations_input)
        schemas = {}
        executables = {}

        locations_input.each do |location, input|
          schema = input[:schema]

          if schema.nil?
            raise ComposerError, "A schema is required for `#{location}` location."
          elsif !(schema.is_a?(Class) && schema <= GraphQL::Schema)
            raise ComposerError, "The schema for `#{location}` location must be a GraphQL::Schema class."
          end

          input.fetch(:stitch, GraphQL::Stitching::EMPTY_ARRAY).each do |dir|
            type = dir[:parent_type_name] ? schema.types[dir[:parent_type_name]] : schema.query
            raise ComposerError, "Invalid stitch directive type `#{dir[:parent_type_name]}`" unless type

            field = type.fields[dir[:field_name]]
            raise ComposerError, "Invalid stitch directive field `#{dir[:field_name]}`" unless field

            field_path = "#{location}.#{field.name}"
            @stitch_directives[field_path] ||= []
            @stitch_directives[field_path] << dir.slice(:key, :type_name)
          end

          federation_entity_type = schema.types["_Entity"]
          if federation_entity_type && federation_entity_type.kind.union? && schema.query.fields["_entities"]&.type&.unwrap == federation_entity_type
            schema.possible_types(federation_entity_type).each do |entity_type|
              entity_type.directives.each do |directive|
                next unless directive.graphql_name == "key"

                key = directive.arguments.keyword_arguments.fetch(:fields).strip
                raise ComposerError, "Composite federation keys are not supported." unless /^\w+$/.match?(key)

                field_path = "#{location}._entities"
                @stitch_directives[field_path] ||= []
                @stitch_directives[field_path] << {
                  key: key,
                  type_name: entity_type.graphql_name,
                  federation: true,
                }
              end
            end
          end

          schemas[location.to_s] = schema
          executables[location.to_s] = input[:executable] || schema
        end

        return schemas, executables
      end

      # @!scope class
      # @!visibility private
      def build_directive(directive_name, directives_by_location)
        builder = self

        Class.new(GraphQL::Schema::Directive) do
          graphql_name(directive_name)
          description(builder.merge_descriptions(directive_name, directives_by_location))
          repeatable(directives_by_location.values.any?(&:repeatable?))
          locations(*directives_by_location.values.flat_map(&:locations).tap(&:uniq!))
          builder.build_merged_arguments(directive_name, directives_by_location, self, directive_name: directive_name)
        end
      end

      # @!scope class
      # @!visibility private
      def build_scalar_type(type_name, types_by_location)
        built_in_type = GraphQL::Schema::BUILT_IN_TYPES[type_name]
        return built_in_type if built_in_type

        builder = self

        Class.new(GraphQL::Schema::Scalar) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_enum_type(type_name, types_by_location, enum_usage)
        builder = self

        # "value" => "location" => enum_value
        enum_values_by_name_location = types_by_location.each_with_object({}) do |(location, type_candidate), memo|
          type_candidate.enum_values.each do |enum_value_candidate|
            memo[enum_value_candidate.graphql_name] ||= {}
            memo[enum_value_candidate.graphql_name][location] = enum_value_candidate
          end
        end

        # intersect input enum types
        if enum_usage.fetch(type_name, EMPTY_ARRAY).include?(:write)
          enum_values_by_name_location.reject! do |value, enum_values_by_location|
            types_by_location.keys.length != enum_values_by_location.keys.length
          end
        end

        Class.new(GraphQL::Schema::Enum) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_directives(type_name, types_by_location, self)

          enum_values_by_name_location.each do |value_name, enum_values_by_location|
            enum_value = value(value_name,
              value: value_name,
              description: builder.merge_descriptions(type_name, enum_values_by_location, enum_value: value_name),
              deprecation_reason: builder.merge_deprecations(type_name, enum_values_by_location, enum_value: value_name),
            )

            builder.build_merged_directives(type_name, enum_values_by_location, enum_value, enum_value: value_name)
          end
        end
      end

      # @!scope class
      # @!visibility private
      def build_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Object) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.tap(&:uniq!).each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_interface_type(type_name, types_by_location)
        builder = self

        Module.new do
          include GraphQL::Schema::Interface
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.tap(&:uniq!).each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_union_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Union) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          possible_names = types_by_location.values.flat_map { _1.possible_types.map(&:graphql_name) }.tap(&:uniq!)
          possible_types(*possible_names.map { builder.build_type_binding(_1) })
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_input_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::InputObject) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_arguments(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_type_binding(type_name)
        GraphQL::Schema::LateBoundType.new(@mapped_type_names.fetch(type_name, type_name))
      end

      # @!scope class
      # @!visibility private
      def build_merged_fields(type_name, types_by_location, owner)
        # "field_name" => "location" => field
        fields_by_name_location = types_by_location.each_with_object({}) do |(location, type_candidate), memo|
          @field_map[type_name] ||= {}
          type_candidate.fields.each do |field_name, field_candidate|
            @field_map[type_name][field_candidate.name] ||= []
            @field_map[type_name][field_candidate.name] << location

            memo[field_name] ||= {}
            memo[field_name][location] = field_candidate
          end
        end

        fields_by_name_location.each do |field_name, fields_by_location|
          value_types = fields_by_location.values.map(&:type)

          type = merge_value_types(type_name, value_types, field_name: field_name)
          schema_field = owner.field(
            field_name,
            description: merge_descriptions(type_name, fields_by_location, field_name: field_name),
            deprecation_reason: merge_deprecations(type_name, fields_by_location, field_name: field_name),
            type: Util.unwrap_non_null(type),
            null: !type.non_null?,
            camelize: false,
          )

          build_merged_arguments(type_name, fields_by_location, schema_field, field_name: field_name)
          build_merged_directives(type_name, fields_by_location, schema_field, field_name: field_name)
        end
      end

      # @!scope class
      # @!visibility private
      def build_merged_arguments(type_name, members_by_location, owner, field_name: nil, directive_name: nil)
        # "argument_name" => "location" => argument
        args_by_name_location = members_by_location.each_with_object({}) do |(location, member_candidate), memo|
          member_candidate.arguments.each do |argument_name, argument|
            memo[argument_name] ||= {}
            memo[argument_name][location] = argument
          end
        end

        args_by_name_location.each do |argument_name, arguments_by_location|
          value_types = arguments_by_location.values.map(&:type)

          if arguments_by_location.length != members_by_location.length
            if value_types.any?(&:non_null?)
              path = [type_name, field_name, argument_name].compact.join(".")
              raise ComposerError, "Required argument `#{path}` must be defined in all locations." # ...or hidden?
            end
            next
          end

          # Getting double args sometimes on auto-generated connection types... why?
          next if owner.arguments.any? { _1.first == argument_name }

          kwargs = {}
          default_values_by_location = arguments_by_location.each_with_object({}) do |(location, argument), memo|
            next if argument.default_value == NO_DEFAULT_VALUE
            memo[location] = argument.default_value
          end

          if default_values_by_location.any?
            kwargs[:default_value] = @default_value_merger.call(default_values_by_location, {
              type_name: type_name,
              field_name: field_name,
              argument_name: argument_name,
              directive_name: directive_name,
            }.tap(&:compact!))
          end

          type = merge_value_types(type_name, value_types, argument_name: argument_name, field_name: field_name)
          schema_argument = owner.argument(
            argument_name,
            description: merge_descriptions(type_name, arguments_by_location, argument_name: argument_name, field_name: field_name),
            deprecation_reason: merge_deprecations(type_name, arguments_by_location, argument_name: argument_name, field_name: field_name),
            type: Util.unwrap_non_null(type),
            required: type.non_null?,
            camelize: false,
            **kwargs,
          )

          build_merged_directives(type_name, arguments_by_location, schema_argument, field_name: field_name, argument_name: argument_name)
        end
      end

      # @!scope class
      # @!visibility private
      def build_merged_directives(type_name, members_by_location, owner, field_name: nil, argument_name: nil, enum_value: nil)
        directives_by_name_location = members_by_location.each_with_object({}) do |(location, member_candidate), memo|
          member_candidate.directives.each do |directive|
            memo[directive.graphql_name] ||= {}
            memo[directive.graphql_name][location] = directive
          end
        end

        directives_by_name_location.each do |directive_name, directives_by_location|
          directive_class = @schema_directives[directive_name]
          next unless directive_class

          # handled by deprecation_reason merger...
          next if directive_class.graphql_name == "deprecated"

          kwarg_values_by_name_location = directives_by_location.each_with_object({}) do |(location, directive), memo|
            directive.arguments.keyword_arguments.each do |key, value|
              key = key.to_s
              next unless directive_class.arguments[key]

              memo[key] ||= {}
              memo[key][location] = value
            end
          end

          kwargs = kwarg_values_by_name_location.each_with_object({}) do |(kwarg_name, kwarg_values_by_location), memo|
            memo[kwarg_name.to_sym] = @directive_kwarg_merger.call(kwarg_values_by_location, {
              type_name: type_name,
              field_name: field_name,
              argument_name: argument_name,
              enum_value: enum_value,
              directive_name: directive_name,
              kwarg_name: kwarg_name,
            }.tap(&:compact!))
          end

          owner.directive(directive_class, **kwargs)
        end
      end

      # @!scope class
      # @!visibility private
      def merge_value_types(type_name, type_candidates, field_name: nil, argument_name: nil)
        path = [type_name, field_name, argument_name].tap(&:compact!).join(".")
        alt_structures = type_candidates.map { Util.flatten_type_structure(_1) }
        basis_structure = alt_structures.shift

        alt_structures.each do |alt_structure|
          if alt_structure.length != basis_structure.length
            raise ComposerError, "Cannot compose mixed list structures at `#{path}`."
          end

          if alt_structure.last.name != basis_structure.last.name
            raise ComposerError, "Cannot compose mixed types at `#{path}`."
          end
        end

        type = GraphQL::Schema::BUILT_IN_TYPES.fetch(
          basis_structure.last.name,
          build_type_binding(basis_structure.last.name)
        )

        basis_structure.reverse!.each_with_index do |basis, index|
          rev_index = basis_structure.length - index - 1
          non_null = alt_structures.each_with_object([basis.non_null?]) { |s, m| m << s[rev_index].non_null? }

          type = type.to_list_type if basis.list?
          type = type.to_non_null_type if argument_name ? non_null.any? : non_null.all?
        end

        type
      end

      # @!scope class
      # @!visibility private
      def merge_descriptions(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.description }
        @description_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.tap(&:compact!))
      end

      # @!scope class
      # @!visibility private
      def merge_deprecations(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.deprecation_reason }
        @deprecation_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.tap(&:compact!))
      end

      # @!scope class
      # @!visibility private
      def extract_boundaries(type_name, types_by_location)
        types_by_location.each do |location, type_candidate|
          type_candidate.fields.each do |field_name, field_candidate|
            boundary_type_name = field_candidate.type.unwrap.graphql_name
            boundary_structure = Util.flatten_type_structure(field_candidate.type)
            boundary_kwargs = @stitch_directives["#{location}.#{field_name}"] || []

            field_candidate.directives.each do |directive|
              next unless directive.graphql_name == GraphQL::Stitching.stitch_directive
              boundary_kwargs << directive.arguments.keyword_arguments
            end

            boundary_kwargs.each do |kwargs|
              key = kwargs.fetch(:key)
              impl_type_name = kwargs.fetch(:type_name, boundary_type_name)
              key_selections = GraphQL.parse("{ #{key} }").definitions[0].selections

              if key_selections.length != 1
                raise ComposerError, "Boundary key at #{type_name}.#{field_name} must specify exactly one key."
              end

              argument_name = key_selections[0].alias
              argument_name ||= if field_candidate.arguments.size == 1
                field_candidate.arguments.keys.first
              elsif field_candidate.arguments[key]
                key
              end

              argument = field_candidate.arguments[argument_name]
              unless argument
                raise ComposerError, "No boundary argument matched for #{type_name}.#{field_name}.#{argument_name}. Specify a key alias."
              end

              argument_structure = Util.flatten_type_structure(argument.type)
              if argument_structure.length != boundary_structure.length
                raise ComposerError, "Mismatched input/output for #{type_name}.#{field_name}.#{argument_name} boundary. Arguments must map directly to results."
              end

              @boundary_map[impl_type_name] ||= []
              @boundary_map[impl_type_name] << Boundary.new(
                location: location,
                type_name: impl_type_name,
                key: key_selections[0].name,
                field: field_candidate.name,
                arg: argument_name,
                list: boundary_structure.first.list?,
                federation: kwargs[:federation] || false,
              )
            end
          end
        end
      end

      # @!scope class
      # @!visibility private
      def select_root_field_locations(schema)
        [schema.query, schema.mutation].tap(&:compact!).each do |root_type|
          root_type.fields.each do |root_field_name, root_field|
            root_field_locations = @field_map[root_type.graphql_name][root_field_name]
            next unless root_field_locations.length > 1

            target_location = @root_field_location_selector.call(root_field_locations, {
              type_name: root_type.graphql_name,
              field_name: root_field_name,
            })
            next unless root_field_locations.include?(target_location)

            root_field_locations.reject! { _1 == target_location }
            root_field_locations.unshift(target_location)
          end
        end
      end

      # @!scope class
      # @!visibility private
      def expand_abstract_boundaries(schema)
        @boundary_map.keys.each do |type_name|
          boundary_type = schema.types[type_name]
          next unless boundary_type.kind.abstract?

          expanded_types = Util.expand_abstract_type(schema, boundary_type)
          expanded_types.select { @candidate_types_by_name_and_location[_1.graphql_name].length > 1 }.each do |expanded_type|
            @boundary_map[expanded_type.graphql_name] ||= []
            @boundary_map[expanded_type.graphql_name].push(*@boundary_map[type_name])
          end
        end
      end

      # @!scope class
      # @!visibility private
      def build_enum_usage_map(schemas)
        reads = []
        writes = []

        schemas.each do |schema|
          introspection_types = schema.introspection_system.types.keys
          schema.types.each_value do |type|
            next if introspection_types.include?(type.graphql_name)

            if type.kind.object? || type.kind.interface?
              type.fields.each_value do |field|
                field_type = field.type.unwrap
                reads << field_type.graphql_name if field_type.kind.enum?

                field.arguments.each_value do |argument|
                  argument_type = argument.type.unwrap
                  writes << argument_type.graphql_name if argument_type.kind.enum?
                end
              end

            elsif type.kind.input_object?
              type.arguments.each_value do |argument|
                argument_type = argument.type.unwrap
                writes << argument_type.graphql_name if argument_type.kind.enum?
              end
            end
          end
        end

        usage = reads.tap(&:uniq!).each_with_object({}) do |enum_name, memo|
          memo[enum_name] ||= []
          memo[enum_name] << :read
        end
        writes.tap(&:uniq!).each_with_object(usage) do |enum_name, memo|
          memo[enum_name] ||= []
          memo[enum_name] << :write
        end
      end

      private

      def reset!
        @field_map = {}
        @boundary_map = {}
        @mapped_type_names = {}
        @candidate_directives_by_name_and_location = nil
        @schema_directives = nil
      end
    end
  end
end
