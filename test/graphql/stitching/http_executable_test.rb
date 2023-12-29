# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::HttpExecutable" do

  class UploadSchema < GraphQL::Schema
    class Upload < GraphQL::Schema::Scalar
      graphql_name "Upload"
    end

    class FileInput < GraphQL::Schema::InputObject
      graphql_name "FileInput"

      argument :file, Upload, required: false
      argument :files, [Upload], required: false
      argument :deep, [[Upload]], required: false
      argument :nested, FileInput, required: false
    end

    class Root < GraphQL::Schema::Object
      field :upload, Boolean, null: true do
        argument :input, FileInput, required: true
      end
      field :uploads, Boolean, null: true do
        argument :inputs, [FileInput], required: true
      end
    end

    query Root
  end

  DummyFile = Struct.new(:tempfile)

  def setup
    @supergraph = GraphQL::Stitching::Supergraph.new(schema: UploadSchema)
  end

  def test_extract_multipart_form
    file1 = DummyFile.new("A")
    file2 = DummyFile.new("B")
    document = %|
      mutation($input: FileInput!, $inputs: [FileInput]!) {
        upload(input: $input)
        uploads(inputs: $inputs)
      }
    |
    variables = {
      "input" => {
        "file" => file1,
        "files" => [file1, file2],
      },
      "inputs" => [{
        "file" => file1,
        "files" => [file1, file2],
      },{
        "file" => file1,
        "files" => [file1, file2],
      }]
    }

    request = GraphQL::Stitching::Request.new(
      @supergraph,
      document,
      variables: variables
    )

    exe = GraphQL::Stitching::HttpExecutable.new(
      url: "",
      upload_types: ["Upload"],
    )

    result = exe.extract_multipart_form(document, variables, request).tap do |r|
      r["operations"] = JSON.parse(r["operations"])
      r["map"] = JSON.parse(r["map"])
    end

    expected = {
      "operations" => {
        "query" => document,
        "variables" => {
          "input" => {
            "file" => nil,
            "files" => [nil, nil],
          },
          "inputs" => [{
            "file" => nil,
            "files" => [nil, nil],
          }, {
            "file" => nil,
            "files" => [nil, nil],
          }]
        }
      },
      "map" => {
        "0" => [
          "variables.input.file",
          "variables.input.files.0",
          "variables.inputs.0.file",
          "variables.inputs.0.files.0",
          "variables.inputs.1.file",
          "variables.inputs.1.files.0",
        ],
        "1" => [
          "variables.input.files.1",
          "variables.inputs.0.files.1",
          "variables.inputs.1.files.1",
        ]
      },
      "0" => "A",
      "1" => "B",
    }

    assert_equal expected, result
  end
end
