#!/usr/bin/env ruby

# generate_grammar.rb - Generate GBNF grammar from JSON schema
#
# USAGE:
#   ruby bin/generate_grammar.rb SCHEMA_FILE OUTPUT_FILE [LLAMA_CPP_PATH]
#
# DESCRIPTION:
#   This script generates GBNF (Grammar-Based Next-Token Format) grammar
#   files from JSON schemas for use with llama.cpp constrained generation.
#   It first tries to use llama.cpp's json_schema_to_grammar.py script,
#   and falls back to a built-in grammar generator if that's not available.
#
# ARGUMENTS:
#   SCHEMA_FILE     Path to JSON schema file
#   OUTPUT_FILE     Path to output GBNF grammar file
#   LLAMA_CPP_PATH  Optional path to llama.cpp directory
#
# EXAMPLES:
#   ruby bin/generate_grammar.rb schema/biosample_schema.json grammar/biosample.gbnf
#   ruby bin/generate_grammar.rb schema/biosample_schema.json grammar/biosample.gbnf ~/repos/llama.cpp
#

require 'json'
require 'open3'
require 'fileutils'

class GrammarGenerator
  def self.generate_from_schema(schema_file, output_file, llama_cpp_path = nil)
    unless File.exist?(schema_file)
      puts "Error: Schema file not found: #{schema_file}"
      return false
    end

    # Create output directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(output_file))

    # Try to use llama.cpp's json_schema_to_grammar.py first
    llama_cpp_path ||= detect_llama_cpp_path
    if llama_cpp_path && try_llama_cpp_generator(schema_file, output_file, llama_cpp_path)
      return true
    end

    # Fall back to built-in grammar generation
    puts "Falling back to built-in grammar generation"
    generate_builtin_grammar(schema_file, output_file)
  end

  private

  def self.try_llama_cpp_generator(schema_file, output_file, llama_cpp_path)
    grammar_script = File.join(File.expand_path(llama_cpp_path), 'examples', 'json_schema_to_grammar.py')

    unless File.exist?(grammar_script)
      puts "Warning: json_schema_to_grammar.py not found at #{grammar_script}"
      return false
    end

    puts "Using llama.cpp grammar generator: #{grammar_script}"

    cmd = ['python3', grammar_script, schema_file]
    stdout, stderr, status = Open3.capture3(*cmd)

    unless status.success?
      puts "Warning: Grammar generation failed: #{stderr}"
      return false
    end

    File.write(output_file, stdout)
    puts "Grammar generated successfully using llama.cpp: #{output_file}"
    true
  rescue => e
    puts "Warning: Error running llama.cpp grammar generator: #{e.message}"
    false
  end

  def self.generate_builtin_grammar(schema_file, output_file)
    begin
      schema = JSON.parse(File.read(schema_file))
    rescue JSON::ParserError => e
      puts "Error: Invalid JSON schema: #{e.message}"
      return false
    end

    # Generate grammar based on schema structure
    if schema['type'] == 'object' && schema['properties']
      grammar = generate_object_grammar(schema)
    else
      puts "Error: Unsupported schema structure. Only object schemas are supported."
      return false
    end

    File.write(output_file, grammar)
    puts "Built-in grammar generated: #{output_file}"
    true
  rescue => e
    puts "Error: Grammar generation failed: #{e.message}"
    false
  end

  def self.generate_object_grammar(schema)
    properties = schema['properties']
    required = schema['required'] || []

    # Special case for our BioSample schema
    if properties.keys.sort == ['disease', 'gene-modification', 'treatments']
      return generate_biosample_grammar
    end

    # General object grammar generation
    generate_general_object_grammar(properties, required)
  end

  def self.generate_biosample_grammar
    <<~GBNF
      root ::= object
      object ::= "{" ws "\"disease\"" ws ":" ws boolean ws "," ws "\"treatments\"" ws ":" ws boolean ws "," ws "\"gene-modification\"" ws ":" ws boolean ws "}"
      boolean ::= "true" | "false"
      ws ::= [ \\t\\n\\r]*
    GBNF
  end

  def self.generate_general_object_grammar(properties, required)
    # This is a simplified version for general objects
    # For production use, you'd want a more sophisticated grammar generator
    property_rules = []
    properties.each do |key, prop|
      case prop['type']
      when 'boolean'
        property_rules << "\"#{key}\" ws \":\"] ws boolean"
      when 'string'
        property_rules << "\"#{key}\" ws \":\" ws string"
      when 'number'
        property_rules << "\"#{key}\" ws \":\" ws number"
      end
    end

    <<~GBNF
      root ::= object
      object ::= "{" ws (#{property_rules.map { |rule| "(" + rule + ")" }.join(' ws "," ws ')}) ws "}"
      boolean ::= "true" | "false"
      string ::= "\\"" ([^"\\\\] | "\\\\" .)* "\\""
      number ::= [0-9]+ ("." [0-9]+)? ([eE] [+-]? [0-9]+)?
      ws ::= [ \\t\\n\\r]*
    GBNF
  end

  def self.detect_llama_cpp_path
    # Try common locations and environment variables
    paths = [
      ENV['LLAMA_CPP_PATH'],
      "~/repos/llama.cpp",
      "/usr/local/llama.cpp",
      "/opt/llama.cpp",
      "/usr/local/share/llama.cpp"
    ].compact.map { |path| File.expand_path(path) }

    paths.find do |path|
      File.exist?(path) && File.exist?(File.join(path, 'examples', 'json_schema_to_grammar.py'))
    end
  end
end

# Command line interface
if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: ruby bin/generate_grammar.rb SCHEMA_FILE OUTPUT_FILE [LLAMA_CPP_PATH]"
    puts
    puts "Examples:"
    puts "  ruby bin/generate_grammar.rb schema/biosample_schema.json grammar/biosample.gbnf"
    puts "  ruby bin/generate_grammar.rb schema/biosample_schema.json grammar/biosample.gbnf ~/repos/llama.cpp"
    exit 1
  end

  schema_file = ARGV[0]
  output_file = ARGV[1]
  llama_cpp_path = ARGV[2]

  success = GrammarGenerator.generate_from_schema(schema_file, output_file, llama_cpp_path)
  exit(success ? 0 : 1)
end
