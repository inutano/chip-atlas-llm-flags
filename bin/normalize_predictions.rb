#!/usr/bin/env ruby

# normalize_predictions.rb - Normalizes LLM prediction outputs
#
# USAGE:
#   ruby bin/normalize_predictions.rb INPUT_JSONL [--outdir OUTDIR]
#
# DESCRIPTION:
#   This script processes JSONL files from LLM inference (run_llama_local.rb
#   or run_vllm.rb) and produces normalized compact records with only the
#   essential prediction data.
#
# ARGUMENTS:
#   INPUT_JSONL   Path to LLM prediction JSONL file
#   --outdir      Output directory (optional, defaults to current directory)
#
# OUTPUT:
#   Compact JSONL records with format:
#   {"id":"SAMN...","disease":true,"treatments":false,"gene-modification":true}
#
# PROCESSING:
#   - Extracts only id and prediction fields
#   - Keeps most recent entry for duplicated IDs
#   - Filters out records with error flags
#   - Logs processing statistics
#
# EXAMPLES:
#   ruby bin/normalize_predictions.rb biosample_predictions_20231201_120000.jsonl
#   ruby bin/normalize_predictions.rb predictions.jsonl --outdir output/
#

require 'json'
require 'optparse'
require 'time'
require 'fileutils'

class PredictionNormalizer
  def initialize(input_file, output_dir = '.')
    @input_file = input_file
    @output_dir = output_dir
    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    @output_file = File.join(@output_dir, "normalized_predictions_#{@timestamp}.jsonl")
    @log_file = File.join(@output_dir, "normalized_predictions_#{@timestamp}.log")

    # Statistics
    @total_records = 0
    @valid_records = 0
    @flagged_records = 0
    @duplicate_records = 0
    @final_records = 0

    # Track records by ID (keep most recent)
    @records_by_id = {}

    setup_logging
  end

  def run
    validate_inputs

    log "Starting prediction normalization on #{@input_file}"
    log "Output file: #{@output_file}"
    log "Log file: #{@log_file}"

    start_time = Time.now

    # Process input file
    process_input_file

    # Write normalized output
    write_normalized_output

    total_time = Time.now - start_time
    print_summary(total_time)
  end

  private

  def setup_logging
    FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)
    @log_handle = File.open(@log_file, 'w')
  end

  def log(message)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    log_msg = "[#{timestamp}] #{message}"
    puts log_msg
    @log_handle.puts log_msg
    @log_handle.flush
  end

  def validate_inputs
    unless File.exist?(@input_file)
      raise "Input file not found: #{@input_file}"
    end
  end

  def process_input_file
    log "Reading and processing input file..."

    File.foreach(@input_file) do |line|
      line = line.strip
      next if line.empty?

      @total_records += 1
      process_record(line)

      # Log progress every 1000 records
      if (@total_records % 1000) == 0
        log "Processed #{@total_records} records..."
      end
    end
  end

  def process_record(line)
    begin
      record = JSON.parse(line)

      # Validate record structure
      unless record.is_a?(Hash) && record['id'] && record['prediction']
        log "WARN: Invalid record structure at line #{@total_records}"
        return
      end

      id = record['id']
      prediction = record['prediction']

      # Skip records with error flags
      if record['flag']
        @flagged_records += 1
        log "INFO: Skipping record #{id} with flag: #{record['flag']}"
        return
      end

      # Validate prediction structure
      unless prediction.is_a?(Hash) &&
             prediction.has_key?('disease') &&
             prediction.has_key?('treatments') &&
             prediction.has_key?('gene-modification')
        log "WARN: Invalid prediction structure for record #{id}"
        return
      end

      @valid_records += 1

      # Check for duplicates (keep most recent)
      if @records_by_id.has_key?(id)
        @duplicate_records += 1
        log "INFO: Duplicate ID #{id} found, keeping most recent"
      end

      # Store normalized record
      normalized_record = {
        'id' => id,
        'disease' => !!prediction['disease'],
        'treatments' => !!prediction['treatments'],
        'gene-modification' => !!prediction['gene-modification']
      }

      @records_by_id[id] = normalized_record

    rescue JSON::ParserError => e
      log "ERROR: Invalid JSON at line #{@total_records}: #{e.message}"
    rescue => e
      log "ERROR: Failed to process record at line #{@total_records}: #{e.message}"
    end
  end

  def write_normalized_output
    log "Writing normalized output..."

    @final_records = @records_by_id.length

    File.open(@output_file, 'w') do |output|
      @records_by_id.each_value do |record|
        output.puts JSON.generate(record)
      end
    end
  end

  def print_summary(total_time)
    log "\n" + "="*60
    log "NORMALIZATION SUMMARY"
    log "="*60
    log "Total processing time: #{total_time.round(2)} seconds"
    log "Total records read: #{@total_records}"
    log "Valid prediction records: #{@valid_records}"
    log "Flagged records (skipped): #{@flagged_records}"
    log "Duplicate records (merged): #{@duplicate_records}"
    log "Final normalized records: #{@final_records}"
    log ""
    log "Output file: #{@output_file}"
    log "Log file: #{@log_file}"
    log "="*60

    if @final_records > 0
      log "Normalization completed successfully!"
    else
      log "WARNING: No valid records found to normalize!"
    end

    @log_handle.close
  end
end

def parse_arguments
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby bin/normalize_predictions.rb INPUT_JSONL [--outdir OUTDIR]"

    opts.on("--outdir OUTDIR", "Output directory (default: current directory)") do |outdir|
      options[:outdir] = outdir
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  # Validate required argument
  if ARGV.empty?
    puts "Error: INPUT_JSONL file is required"
    puts "Usage: ruby bin/normalize_predictions.rb INPUT_JSONL [--outdir OUTDIR]"
    exit 1
  end

  options[:input_file] = ARGV[0]
  options[:outdir] ||= '.'

  options
end

# Main execution
if __FILE__ == $0
  begin
    options = parse_arguments
    normalizer = PredictionNormalizer.new(options[:input_file], options[:outdir])
    normalizer.run
  rescue => e
    puts "FATAL ERROR: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end
