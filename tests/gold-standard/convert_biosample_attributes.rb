#!/usr/bin/env ruby

require 'json'

class BioSampleConverter
  def initialize(input_file, output_file)
    @input_file = input_file
    @output_file = output_file
  end

  def convert
    File.open(@output_file, 'w') do |output|
      File.foreach(@input_file) do |line|
        line.strip!
        next if line.empty?

        begin
          record = JSON.parse(line)
          converted_record = convert_record(record)
          if converted_record
            output.puts(JSON.generate(converted_record))
          else
            STDERR.puts "Warning: Skipping record #{record['biosample_id']} - no valid data to convert"
          end
        rescue JSON::ParserError => e
          STDERR.puts "Error parsing JSON line: #{e.message}"
          STDERR.puts "Line: #{line[0..100]}..." if line.length > 100
          next
        rescue => e
          STDERR.puts "Error processing record: #{e.message}"
          STDERR.puts "Record ID: #{record['biosample_id'] rescue 'unknown'}"
          next
        end
      end
    end

    puts "Conversion complete. Output written to #{@output_file}"
  end

  private

  def convert_record(record)
    return nil unless record && record['biosample_id']

    converted = {
      'biosample_id' => record['biosample_id'],
      'srx' => record['srx']
    }

    # Extract basic metadata
    entry = record['entry']
    if entry
      converted['accession'] = entry['accession']
      converted['organism'] = extract_organism(entry)
      converted['title'] = entry.dig('Description', 'Title')

      # Convert attributes from redundant structure to simple key=value
      attributes = convert_attributes(entry['Attributes'])
      converted['attributes'] = attributes if attributes && !attributes.empty?
    end

    # Only return record if it has meaningful content
    if converted['attributes'] || converted['organism'] || converted['title']
      converted
    else
      nil
    end
  end

  def extract_organism(entry)
    organism_info = entry.dig('Description', 'Organism')
    return nil unless organism_info

    {
      'taxonomy_id' => organism_info['taxonomy_id'],
      'taxonomy_name' => organism_info['taxonomy_name']
    }
  end

  def convert_attributes(attributes_section)
    return nil unless attributes_section && attributes_section['Attribute']

    attribute_list = attributes_section['Attribute']
    # Handle both single attribute (hash) and multiple attributes (array)
    attribute_list = [attribute_list] unless attribute_list.is_a?(Array)

    converted_attrs = {}

    attribute_list.each do |attr|
      next unless attr.is_a?(Hash)

      # Determine the best key name to use
      key = determine_attribute_key(attr)
      value = attr['content']

      # Skip attributes without content or valid key
      next unless key && !key.strip.empty? && value && !value.strip.empty?

      converted_attrs[key] = value.strip
    end

    converted_attrs.empty? ? nil : converted_attrs
  end

  def determine_attribute_key(attr)
    return nil unless attr.is_a?(Hash)

    # Priority: harmonized_name > attribute_name
    # This provides the most standardized key names
    harmonized = attr['harmonized_name']
    original = attr['attribute_name']

    # Use harmonized_name if available, otherwise use attribute_name
    raw_key = if harmonized && !harmonized.to_s.strip.empty?
                harmonized
              elsif original && !original.to_s.strip.empty?
                original
              else
                return nil
              end

    # Clean up the key by replacing spaces/special chars with underscores
    key = raw_key.to_s.strip.downcase

    # Normalize key format: replace spaces and special characters with underscores
    key = key.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/^_|_$/, '')

    key.empty? ? nil : key
  end
end

def show_usage
  puts "Usage: #{$0} <input_file> [output_file]"
  puts "  input_file:  Path to input JSONL file with BioSample records"
  puts "  output_file: Path to output JSONL file (default: input_file with _converted suffix)"
  puts ""
  puts "Example:"
  puts "  #{$0} input.jsonl output.jsonl"
  puts "  #{$0} input.jsonl  # Creates input_converted.jsonl"
end

def analyze_sample_attributes(input_file, num_samples = 10)
  puts "Analyzing attribute structure from #{num_samples} random samples..."
  puts "=" * 60

  lines = File.readlines(input_file)
  sample_lines = lines.sample(num_samples)

  all_attributes = {}

  sample_lines.each_with_index do |line, idx|
    begin
      record = JSON.parse(line.strip)
      attrs = record.dig('entry', 'Attributes', 'Attribute')
      next unless attrs

      attrs = [attrs] unless attrs.is_a?(Array)

      puts "\nSample #{idx + 1} (#{record['biosample_id']}):"
      puts "-" * 40

      attrs.each do |attr|
        attr_name = attr['attribute_name']
        harmonized = attr['harmonized_name']
        display = attr['display_name']
        content = attr['content']

        key = harmonized && !harmonized.strip.empty? ? harmonized : attr_name
        key = key.to_s.strip.downcase.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/^_|_$/, '')

        puts "  #{key} = #{content}"
        puts "    (original: #{attr_name}, harmonized: #{harmonized}, display: #{display})" if harmonized || display

        all_attributes[key] ||= []
        all_attributes[key] << content
      end
    rescue JSON::ParserError => e
      STDERR.puts "Error parsing sample #{idx + 1}: #{e.message}"
    end
  end

  puts "\n" + "=" * 60
  puts "Summary of all unique attribute keys found:"
  all_attributes.keys.sort.each do |key|
    example_values = all_attributes[key].uniq.first(3)
    puts "  #{key} (#{all_attributes[key].size} occurrences, examples: #{example_values.join(', ')})"
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.include?('-h') || ARGV.include?('--help')
    show_usage
    exit 0
  end

  if ARGV.include?('--analyze') || ARGV.include?('-a')
    input_file = ARGV.find { |arg| !arg.start_with?('-') }
    unless input_file && File.exist?(input_file)
      puts "Error: Please provide a valid input file for analysis"
      show_usage
      exit 1
    end

    num_samples = 10
    if idx = ARGV.index('--samples')
      num_samples = ARGV[idx + 1].to_i if ARGV[idx + 1]
    end

    analyze_sample_attributes(input_file, num_samples)
    exit 0
  end

  input_file = ARGV[0]
  output_file = ARGV[1]

  unless input_file
    show_usage
    exit 1
  end

  unless File.exist?(input_file)
    puts "Error: Input file '#{input_file}' not found"
    exit 1
  end

  # Default output file name if not specified
  unless output_file
    base_name = File.basename(input_file, File.extname(input_file))
    dir_name = File.dirname(input_file)
    output_file = File.join(dir_name, "#{base_name}_converted.jsonl")
  end

  converter = BioSampleConverter.new(input_file, output_file)
  converter.convert
end
