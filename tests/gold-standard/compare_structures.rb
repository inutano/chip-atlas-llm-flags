#!/usr/bin/env ruby

require 'json'

class StructureComparator
  def initialize(original_file, converted_file)
    @original_file = original_file
    @converted_file = converted_file
  end

  def compare
    puts "BioSample Structure Comparison"
    puts "=" * 50

    original_stats = analyze_file(@original_file, "Original")
    converted_stats = analyze_file(@converted_file, "Converted")

    puts "\nComparison Summary:"
    puts "-" * 30

    size_reduction = ((original_stats[:total_size] - converted_stats[:total_size]).to_f / original_stats[:total_size] * 100).round(1)
    puts "File size reduction: #{size_reduction}%"
    puts "Original size: #{format_bytes(original_stats[:total_size])}"
    puts "Converted size: #{format_bytes(converted_stats[:total_size])}"

    puts "\nStructure complexity reduction:"
    puts "Original avg attributes per record: #{original_stats[:avg_attrs]}"
    puts "Converted avg attributes per record: #{converted_stats[:avg_attrs]}"

    puts "\nAttribute key standardization:"
    puts "Original unique keys: #{original_stats[:unique_keys].size}"
    puts "Converted unique keys: #{converted_stats[:unique_keys].size}"

    puts "\nSample attribute access patterns:"
    puts "\nOriginal (nested access):"
    puts "  record['entry']['Attributes']['Attribute'][0]['content']"
    puts "\nConverted (direct access):"
    puts "  record['attributes']['cell_type']"

    compare_sample_records
  end

  private

  def analyze_file(file_path, label)
    puts "\n#{label} Structure Analysis:"
    puts "-" * 25

    total_size = File.size(file_path)
    record_count = 0
    total_attrs = 0
    unique_keys = Set.new

    File.foreach(file_path) do |line|
      line.strip!
      next if line.empty?

      record_count += 1
      record = JSON.parse(line)

      if label == "Original"
        attrs = record.dig('entry', 'Attributes', 'Attribute')
        if attrs
          attrs = [attrs] unless attrs.is_a?(Array)
          total_attrs += attrs.size
          attrs.each do |attr|
            key = attr['harmonized_name'] || attr['attribute_name']
            unique_keys.add(key.to_s.downcase.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/^_|_$/, '')) if key
          end
        end
      else
        attrs = record['attributes'] || {}
        total_attrs += attrs.size
        unique_keys.merge(attrs.keys)
      end
    end

    avg_attrs = (total_attrs.to_f / record_count).round(2)

    puts "Records: #{record_count}"
    puts "Total attributes: #{total_attrs}"
    puts "Average attributes per record: #{avg_attrs}"
    puts "File size: #{format_bytes(total_size)}"
    puts "Unique attribute keys: #{unique_keys.size}"

    {
      total_size: total_size,
      record_count: record_count,
      total_attrs: total_attrs,
      avg_attrs: avg_attrs,
      unique_keys: unique_keys
    }
  end

  def compare_sample_records
    puts "\n" + "=" * 50
    puts "Sample Record Comparison"
    puts "=" * 50

    # Get first record from each file
    original_record = JSON.parse(File.readlines(@original_file).first)
    converted_record = JSON.parse(File.readlines(@converted_file).first)

    puts "\nOriginal structure (first record attributes):"
    attrs = original_record.dig('entry', 'Attributes', 'Attribute')
    if attrs
      attrs = [attrs] unless attrs.is_a?(Array)
      attrs.each do |attr|
        puts "  #{attr['attribute_name']} (harmonized: #{attr['harmonized_name']}) = #{attr['content']}"
      end
    end

    puts "\nConverted structure (same record):"
    if converted_record['attributes']
      converted_record['attributes'].each do |key, value|
        puts "  #{key} = #{value}"
      end
    end

    puts "\nJSON size comparison for this record:"
    original_json = JSON.generate(original_record['entry']['Attributes'])
    converted_json = JSON.generate(converted_record['attributes'])

    puts "Original attributes JSON: #{original_json.length} bytes"
    puts "Converted attributes JSON: #{converted_json.length} bytes"
    reduction = ((original_json.length - converted_json.length).to_f / original_json.length * 100).round(1)
    puts "Reduction: #{reduction}%"
  end

  def format_bytes(bytes)
    if bytes < 1024
      "#{bytes} B"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / (1024.0 * 1024)).round(1)} MB"
    end
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.size != 2
    puts "Usage: #{$0} <original_file> <converted_file>"
    puts "Example: #{$0} input.jsonl output_converted.jsonl"
    exit 1
  end

  original_file = ARGV[0]
  converted_file = ARGV[1]

  unless File.exist?(original_file)
    puts "Error: Original file '#{original_file}' not found"
    exit 1
  end

  unless File.exist?(converted_file)
    puts "Error: Converted file '#{converted_file}' not found"
    exit 1
  end

  comparator = StructureComparator.new(original_file, converted_file)
  comparator.compare
end
