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
require 'logger'

class PredictionNormalizer
  def initialize(input_file, output_dir = '.')
    @input_file = input_file
    @base_output_dir = output_dir

    # Use the same directory as the input file if it's in an output directory
    @output_dir = detect_output_directory(@input_file, @base_output_dir)
    @output_file = File.join(@output_dir, "normalized_predictions.jsonl")
    @tsv_output_file = File.join(@output_dir, "normalized_predictions.tsv")
    @log_file = File.join(@output_dir, "normalized_predictions.log")

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

    # Fallback: create new timestamped directory
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    output_dir = File.join(base_output_dir, "output", timestamp)
    FileUtils.mkdir_p(output_dir)
    output_dir
  end

  def run
    validate_inputs

    log(:info, "=== NORMALIZATION START ===")
    log(:info, "Starting prediction normalization on #{@input_file}")
    log(:info, "Output file: #{@output_file}")
    log(:info, "Log file: #{@log_file}")

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

    # Setup dual logger (STDOUT + file)
    @logger = Logger.new(MultiIO.new(STDOUT, File.open(@log_file, 'w')))
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

  def validate_inputs
    unless File.exist?(@input_file)
      raise "Input file not found: #{@input_file}"
    end
  end

  def process_input_file
    log(:info, "Reading and processing input file...")

    File.foreach(@input_file) do |line|
      line = line.strip
      next if line.empty?

      @total_records += 1
      process_record(line)

      # Log progress every 1000 records
      if (@total_records % 1000) == 0
        log(:info, "Processed #{@total_records} records...")
      end
    end
  end

  def process_record(line)
    begin
      record = JSON.parse(line)

      # Validate record structure
      unless record.is_a?(Hash) && record['id'] && record['prediction']
        log(:warn, "Invalid record structure at line #{@total_records}")
        return
      end

      id = record['id']
      prediction = record['prediction']

      # Skip records with error flags
      if record['flag']
        @flagged_records += 1
        log(:info, "Skipping record #{id} with flag: #{record['flag']}")
        return
      end

      # Validate prediction structure
      unless prediction.is_a?(Hash) &&
             prediction.has_key?('disease') &&
             prediction.has_key?('treatments') &&
             prediction.has_key?('gene-modification')
        log(:warn, "Invalid prediction structure for record #{id}")
        return
      end

      @valid_records += 1

      # Check for duplicates (keep most recent)
      if @records_by_id.has_key?(id)
        @duplicate_records += 1
        log(:info, "Duplicate ID #{id} found, keeping most recent")
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
      log(:error, "Invalid JSON at line #{@total_records}: #{e.message}")
    rescue => e
      log(:error, "Failed to process record at line #{@total_records}: #{e.message}")
    end
  end

  def write_normalized_output
    log(:info, "Writing normalized output...")

    @final_records = @records_by_id.length

    # Write JSONL format
    File.open(@output_file, 'w') do |output|
      @records_by_id.each_value do |record|
        output.puts JSON.generate(record)
      end
    end

    # Write TSV format
    write_tsv_output
  end

  def write_tsv_output
    log(:info, "Writing TSV output...")

    require 'csv'

    CSV.open(@tsv_output_file, 'w', col_sep: "\t") do |tsv|
      # Write header
      tsv << ['id', 'disease', 'treatments', 'gene-modification']

      # Write data rows
      @records_by_id.each_value do |record|
        tsv << [
          record['id'],
          record['disease'],
          record['treatments'],
          record['gene-modification']
        ]
      end
    end
  end

  def print_summary(total_time)
    log(:info, "=== NORMALIZATION SUMMARY ===")
    log(:info, "Total processing time: #{total_time.round(2)} seconds")
    log(:info, "Total records read: #{@total_records}")
    log(:info, "Successfully processed: #{@final_records}")
    log(:info, "Skipped records: #{@flagged_records}")
    log(:info, "Failed records: 0")
    log(:info, "Valid prediction records: #{@valid_records}")
    log(:info, "Duplicate records (merged): #{@duplicate_records}")
    log(:info, "Output JSONL file: #{@output_file}")
    log(:info, "Output TSV file: #{@tsv_output_file}")
    log(:info, "Log file: #{@log_file}")

    if @final_records > 0
      log(:info, "=== NORMALIZATION END ===")
    else
      log(:warn, "=== NORMALIZATION END === (No valid records found)")
    end
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
