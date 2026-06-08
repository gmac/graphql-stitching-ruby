# typed: true

module GraphQL::Stitching
  Location = T.type_alias { String }
  TypeName = T.type_alias { String }
  FieldName = T.type_alias { String }
  Variables = T.type_alias { T::Hash[String, T.untyped] }
  RenderedVariables = T.type_alias { T::Hash[String, String] }
  ExecutionResult = T.type_alias { T::Hash[String, T.untyped] }
  Data = T.type_alias { T::Hash[String, T.untyped] }
  GraphQLError = T.type_alias { T::Hash[String, T.untyped] }
  ResponsePath = T.type_alias { T::Array[T.any(String, Integer)] }
  VariablePath = T.type_alias { T::Array[T.any(String, Integer)] }
  MultipartForm = T.type_alias { T::Hash[String, T.untyped] }
  FilesByPath = T.type_alias { T::Hash[VariablePath, T.untyped] }
  OriginEntry = T.type_alias { [Data, ResponsePath] }
  OriginSet = T.type_alias { T::Array[Data] }
  OriginSetsByOperation = T.type_alias { T::Hash[Plan::Op, OriginSet] }
  OriginPathsByOperation = T.type_alias { T::Hash[Plan::Op, T::Array[T.nilable(ResponsePath)]] }
  JsonMap = T.type_alias { T::Hash[String, T.untyped] }
  PublicError = T.type_alias { T::Hash[String, T.untyped] }
  PublicErrorObject = T.type_alias { T.any(GraphQL::ExecutionError, GraphQL::ParseError) }
  DocumentNode = T.type_alias { GraphQL::Language::Nodes::Document }
  OperationNode = T.type_alias { GraphQL::Language::Nodes::OperationDefinition }
  FragmentNode = T.type_alias { GraphQL::Language::Nodes::FragmentDefinition }
  FragmentDefinitions = T.type_alias { T::Hash[String, GraphQL::Language::Nodes::FragmentDefinition] }
  VariableDefinitions = T.type_alias { T::Hash[String, T.untyped] }

  CompositeType = T.type_alias do
    T.any(
      T.class_of(GraphQL::Schema::Object),
      T.class_of(GraphQL::Schema::Interface),
      T.class_of(GraphQL::Schema::Union),
    )
  end

  SelectionNode = T.type_alias do
    T.any(
      GraphQL::Language::Nodes::Field,
      GraphQL::Language::Nodes::InlineFragment,
      GraphQL::Language::Nodes::FragmentSpread,
      FragmentNode,
    )
  end

  SelectionSetNode = T.type_alias do
    T.any(
      GraphQL::Language::Nodes::Field,
      GraphQL::Language::Nodes::InlineFragment,
      OperationNode,
      FragmentNode,
    )
  end

  ArgumentNode = T.type_alias do
    T.any(
      GraphQL::Language::Nodes::Field,
      GraphQL::Language::Nodes::Directive,
      GraphQL::Language::Nodes::InputObject,
    )
  end

  ResolverArgumentTypeMap = T.type_alias { T::Hash[String, T::Array[Util::TypeStructure]] }
  SubgraphTypesByLocation = T.type_alias { T::Hash[Location, T.untyped] }

  Executable = T.type_alias do
    T.any(
      T.class_of(GraphQL::Schema),
      T.proc.params(request: Request, source: String, variables: Variables).returns(T.untyped),
    )
  end

  CacheReadHandler = T.type_alias { T.proc.params(request: Request).returns(T.nilable(String)) }
  CacheWriteHandler = T.type_alias { T.proc.params(request: Request, plan_json: String).void }
  ErrorHandler = T.type_alias { T.proc.params(request: T.nilable(Request), error: StandardError).returns(T.nilable(String)) }

  TypeResolverMap = T.type_alias { T::Hash[TypeName, T::Array[TypeResolver]] }
  TypeResolverRoutes = T.type_alias { T::Hash[Location, T::Array[TypeResolver]] }
  LocationsByType = T.type_alias { T::Hash[TypeName, T::Array[Location]] }
  LocationsByTypeAndField = T.type_alias { T::Hash[TypeName, T::Hash[FieldName, T::Array[Location]]] }
  FieldsByTypeAndLocation = T.type_alias { T::Hash[TypeName, T::Hash[Location, T::Array[FieldName]]] }
end
