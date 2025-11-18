#!/usr/bin/env ruby

# validate_extracted.rb - Validates extracted BioSample JSONL files
#
# USAGE:
#   ruby bin/validate_extracted.rb INPUT_JSONL
#
# DESCRIPTION:
#   This script validates extracted BioSample JSONL files to ensure they meet
#   the expected format and data requirements. It checks each line for valid
#   JSON structure and required field formats.
#
# VALIDATION CHECKS:
#   - Each line must be valid JSON
#   - 'id' field must start with "SAM"
#   - 'attributes' field must be an object (hash)
#   - Missing title, description, or organism are replaced with empty strings
#
# EXIT CODES:
#   0 - All records are valid
#   1 - One or more validation errors found
#
# EXAMPLES:
#   ruby bin/validate_extracted.rb output/biosample_extracted_20231201_120000.jsonl
#

require 'json'
require 'logger'
require 'time'
require 'fileutils'

class ExtractedDataValidator
  def initialize(input_file)
    @input_file = input_file
    @line_number = 0
    @errors = []
    @fixed_records = 0
    @processed_records = 0
    @skipped_records = 0
    @failed_records = 0

    # Use the same directory as the input file if it's in an output directory
    @output_dir = detect_output_directory(@input_file, '.')
    log_file = File.join(@output_dir, "validation.log")

    setup_logger(log_file)
  end

  def detect_output_directory(input_file, base_output_dir)
    # Use the same directory as the input file if it's in an output directory
    input_dir = File.dirname(input_file)
    if input_dir =~ /output\/(\d{8}_\d{6})$/
      return input_dir
    end

    # Try to extract timestamp from input file path
    if input_file =~ /output\/(\d{8}_\d{6})\//
      timestamp_dir = $1
      output_dir = File.join(base_output_dir, "output", timestamp_dir)
      return output_dir if Dir.exist?(output_dir)
    end

    # Fallback: use current directory
    base_output_dir
  end

  def validate
    log(:info, "=== VALIDATION START ===")
    log(:info, "Validating extracted data file: #{@input_file}")

    unless File.exist?(@input_file)
      log(:error, "Input file not found: #{@input_file}")
      exit 1
    end

    File.open(@input_file, 'r') do |file|
      file.each_line do |line|
        @line_number += 1
        validate_line(line.strip)
      end
    end

    print_summary
    exit(@errors.empty? ? 0 : 1)
  end

  private

  def setup_logger(log_file)
    # Setup dual logger (STDOUT + file)
    @logger = Logger.new(MultiIO.new(STDOUT, File.open(log_file, 'w')))
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.iso8601} [#{severity}] #{msg}\n"
    end
  end

  def log(level, message)
    @logger.send(level, message)
  end

  # Dual IO class for logging to multiple outputs
  class MultiIO
    def initialize(*targets)
      @targets = targets
    end

    def write(*args)
      @targets.each { |t| t.write(*args) }
    end

    def close
      @targets.each(&:close)
    end
  end

  def validate_line(line)
    return if line.empty?

    begin
      # Parse JSON
      record = JSON.parse(line)
      validate_record(record)
      @processed_records += 1
    rescue JSON::ParserError => e
      add_error("Invalid JSON: #{e.message}")
      @failed_records += 1
    end
  end

  def validate_record(record)
    unless record.is_a?(Hash)
      add_error("Record is not a JSON object")
      @failed_records += 1
      return
    end

    # Check required id field
    validate_id(record['id'])

    # Check attributes field
    validate_attributes(record['attributes'])

    # Fix missing title, description, organism
    fix_missing_fields(record)
  end

  def validate_id(id)
    if id.nil? || id.to_s.strip.empty?
      add_error("Missing 'id' field")
      @failed_records += 1
    elsif !id.to_s.start_with?('SAM')
      add_error("'id' field does not start with 'SAM': #{id}")
      @failed_records += 1
    end
  end

  def validate_attributes(attributes)
    if attributes.nil?
      add_error("Missing 'attributes' field")
      @failed_records += 1
    elsif !attributes.is_a?(Hash)
      add_error("'attributes' field is not an object: #{attributes.class}")
      @failed_records += 1
    end
  end

  def fix_missing_fields(record)
    fields_fixed = []

    ['title', 'description', 'organism'].each do |field|
      if record[field].nil? || (record[field].respond_to?(:empty?) && record[field].empty?)
        unless record[field] == ""
          record[field] = ""
          fields_fixed << field
        end
      end
    end

    if fields_fixed.any?
      @fixed_records += 1
      log(:info, "Line #{@line_number}: Fixed missing fields: #{fields_fixed.join(', ')}")
    end
  end

  def add_error(message)
    error_msg = "Line #{@line_number}: #{message}"
    @errors << error_msg
    log(:error, error_msg)
  end

  def print_summary
    log(:info, "=== VALIDATION SUMMARY ===")
    log(:info, "Total lines processed: #{@line_number}")
    log(:info, "Successfully processed: #{@processed_records}")
    log(:info, "Records with fixed fields: #{@fixed_records}")
    log(:info, "Skipped records: #{@skipped_records}")
    log(:info, "Failed records: #{@failed_records}")
    log(:info, "Validation errors: #{@errors.length}")

    if @errors.any?
      log(:warn, "ERROR DETAILS:")
      @errors.each { |error| log(:warn, "  #{error}") }
      log(:error, "=== VALIDATION END === (FAILED)")
    else
      log(:info, "=== VALIDATION END === (PASSED)")
    end
  end
end

# Command line argument parsing
def parse_arguments
  if ARGV.empty?
    puts "Usage: ruby bin/validate_extracted.rb INPUT_JSONL"
    puts ""
    puts "Validates extracted BioSample JSONL files for correct format and required fields."
    exit 1
  end

  ARGV[0]
end

# Main execution
if __FILE__ == $0
  input_file = parse_arguments
  validator = ExtractedDataValidator.new(input_file)
  validator.validate
end
