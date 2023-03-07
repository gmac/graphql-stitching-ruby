# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, validate interfaces' do
  def test_errors_for_unmatched_types_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: String! }
      type Gizmo implements Widget { id: ID! value: String! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! value: Int! }
      type Query { b: Gadget }
    |

    assert_error('Incompatible named types between field Gadget.value of type Int! and interface Widget.value of type String!', ValidationError) do
       compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_errors_for_unmatched_list_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: [String]! }
      type Gizmo implements Widget { id: ID! value: [String]! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! value: String! }
      type Query { b: Gadget }
    |

    assert_error('Incompatible list structures between field Gadget.value of type String! and interface Widget.value of type [String]!', ValidationError) do
       compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_errors_for_unmatched_nullability_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: String! }
      type Gizmo implements Widget { id: ID! value: String! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! value: String }
      type Query { b: Gadget }
    |

    assert_error('Incompatible nullability between field Gadget.value of type String and interface Widget.value of type String!', ValidationError) do
       compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_errors_for_missing_fields_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: String! }
      type Gizmo implements Widget { id: ID! value: String! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! }
      type Query { b: Gadget }
    |

    assert_error('Type Gadget does not implement a `value` field in any location, which is required by interface Widget', ValidationError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end
end
