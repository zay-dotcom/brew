# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "sorbet/tapioca/utils"
require "utils/ast"
require "cask/cask"

module Tapioca
  module Compilers
    class Forwardables < Tapioca::Dsl::Compiler
      FORWARDABLE_FILENAME = "forwardable.rb"
      ARRAY_METHODS = T.let(["to_a", "to_ary"].freeze, T::Array[String])
      HASH_METHODS = T.let(["to_h", "to_hash"].freeze, T::Array[String])
      STRING_METHODS = T.let(["to_s", "to_str", "to_json"].freeze, T::Array[String])
      # Use this to override the default return type of a forwarded method:
      DELEGATIONS = T.let({
        "::Cask::Cask" => ::Cask::DSL,
      }.freeze, T::Hash[String, Module])

      ConstantType = type_member { { fixed: Module } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants
        Homebrew::Tapioca::Utils.named_objects_with_module(Forwardable).reject do |obj|
          # Avoid duplicate stubs for forwardables that are defined in vendored gems
          Object.const_source_location(T.must(obj.name))&.first&.include?("vendor/bundle/ruby")
        end
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |klass|
          Homebrew::Tapioca::Utils.methods_from_file(constant, FORWARDABLE_FILENAME)
                                  .each { |method| compile_forwardable_method(klass, method) }
          Homebrew::Tapioca::Utils.methods_from_file(constant, FORWARDABLE_FILENAME, class_methods: true)
                                  .each { |method| compile_forwardable_method(klass, method, class_method: true) }
        end
      end

      private

      sig { params(klass: RBI::Scope, method: T.any(Method, UnboundMethod), class_method: T::Boolean).void }
      def compile_forwardable_method(klass, method, class_method: false)
        name = method.name.to_s
        return_type = return_type(klass.to_s, name)
        klass.create_method(
          name,
          parameters:   [
            create_rest_param("args", type: "T.untyped"),
            create_block_param("block", type: "T.untyped"),
          ],
          return_type:,
          class_method:,
        )
      end

      sig { params(klass: String, name: String).returns(String) }
      def return_type(klass, name)
        if (override = DELEGATIONS[klass]) && override.method_defined?(name)
          signature = T::Utils.signature_for_method(override.instance_method(name))
          signature&.return_type&.to_s || "T.untyped"
        elsif name.end_with?("?") then "T::Boolean"
        elsif ARRAY_METHODS.include?(name) then "Array"
        elsif HASH_METHODS.include?(name) then "Hash"
        elsif STRING_METHODS.include?(name) then "String"
        else
          "T.untyped"
        end
      end
    end
  end
end
