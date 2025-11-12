#!/usr/bin/env ruby

# extract_biosample.rb - BioSample metadata extraction script
#
# USAGE:
#   ruby bin/extract_biosample.rb INPUT_JSON [--outdir OUTDIR]
#
# DESCRIPTION:
#   This script processes a JSON file containing an array of BioSample objects
#   and extracts structured metadata for classification analysis. The script
#   reads BioSample JSON data, validates each record, and outputs processed
#   records in JSONL format for downstream processing.
#
# ARGUMENTS:
#   INPUT_JSON    Path to input JSON file containing BioSample array
#   --outdir      Output directory (optional, defaults to current directory)
#
# OUTPUT FILES:
#   - biosample_extracted_YYYYMMDD_HHMMSS.jsonl - Extracted BioSample records
#   - biosample_extracted_YYYYMMDD_HHMMSS.log    - Processing log file
#
# OUTPUT FORMAT:
#   Each line in the JSONL file contains a JSON object with extracted BioSample
#   metadata including accession, attributes, and raw text for classification.
#
# ERROR HANDLING:
#   - JSON parse errors: Skip record and log the parsing error
#   - Missing BioSample accession: Skip record and log missing accession
#   - Invalid records: Skip and continue processing with detailed logging
#
# LOGGING:
#   Uses Ruby's Logger class to output messages to both STDOUT and log file.
#   Log levels: INFO for normal processing, WARN for skipped records,
#   ERROR for critical issues.
#
# EXAMPLES:
#   ruby bin/extract_biosample.rb data/biosamples.json
#   ruby bin/extract_biosample.rb data/biosamples.json --outdir output/
#

require 'json'
require 'logger'
require 'time'
require 'optparse'

class BioSampleExtractor
  def initialize(input_file, output_dir = '.')
    @input_file = input_file
    @output_dir = output_dir
    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    @output_file = File.join(@output_dir, "biosample_extracted_#{@timestamp}.jsonl")
    @log_file = File.join(@output_dir, "biosample_extracted_#{@timestamp}.log")

    # Initialize counters for summary
    @total_records = 0
    @processed_records = 0
    @skipped_records = 0
    @parse_errors = 0
    @missing_accession_errors = 0

    setup_logger
  end

  def run
    @logger.info "Starting BioSample extraction from #{@input_file}"
    @logger.info "Output file: #{@output_file}"
    @logger.info "Log file: #{@log_file}"

    begin
      process_input_file
      print_summary
    rescue => e
      @logger.error "Fatal error during processing: #{e.message}"
      @logger.error e.backtrace.join("\n")
      exit 1
    end
  end

  private

  def setup_logger
    # Create output directory if it doesn't exist
    Dir.mkdir(@output_dir) unless Dir.exist?(@output_dir)

    # Setup logger to write to both file and STDOUT
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end

    # Also log to file
    @file_logger = Logger.new(@log_file)
    @file_logger.level = Logger::INFO
    @file_logger.formatter = @logger.formatter
  end

  def log_message(level, message)
    @logger.send(level, message)
    @file_logger.send(level, message)
  end

  def process_input_file
    unless File.exist?(@input_file)
      raise "Input file not found: #{@input_file}"
    end

    log_message(:info, "Reading input file: #{@input_file}")

    File.open(@output_file, 'w') do |output|
      begin
        json_content = File.read(@input_file)
        biosamples = JSON.parse(json_content)

        unless biosamples.is_a?(Array)
          raise "Input JSON must contain an array of BioSample objects"
        end

        @total_records = biosamples.length
        log_message(:info, "Found #{@total_records} records to process")

        biosamples.each_with_index do |biosample, index|
          process_biosample(biosample, index, output)
        end

      rescue JSON::ParserError => e
        log_message(:error, "Failed to parse JSON file: #{e.message}")
        raise
      end
    end
  end

  def process_biosample(biosample, index, output)
    begin
      # Validate that biosample is a hash
      unless biosample.is_a?(Hash)
        @skipped_records += 1
        @parse_errors += 1
        log_message(:warn, "Record #{index + 1}: Not a valid object, skipping")
        return
      end

      # Check for required accession field
      accession = biosample['accession'] || biosample['Accession']
      unless accession
        @skipped_records += 1
        @missing_accession_errors += 1
        log_message(:warn, "Record #{index + 1}: Missing BioSample accession, skipping")
        return
      end

      # Extract and structure the biosample data
      extracted_data = extract_biosample_data(biosample, accession)

      # Write to output file
      output.puts(JSON.generate(extracted_data))
      @processed_records += 1

      # Log progress every 1000 records
      if (@processed_records % 1000) == 0
        log_message(:info, "Processed #{@processed_records} records...")
      end

    rescue => e
      @skipped_records += 1
      @parse_errors += 1
      log_message(:warn, "Record #{index + 1}: Error processing - #{e.message}")
    end
  end

  def extract_biosample_data(biosample, accession)
    {
      accession: accession,
      attributes: biosample['attributes'] || biosample['Attributes'] || {},
      title: biosample['title'] || biosample['Title'] || '',
      description: biosample['description'] || biosample['Description'] || '',
      organism: biosample['organism'] || biosample['Organism'] || '',
      extracted_at: Time.now.iso8601,
      raw_text: extract_raw_text(biosample)
    }
  end

  def extract_raw_text(biosample)
    # Combine various text fields for classification analysis
    text_fields = []

    # Add title and description
    text_fields << biosample['title'] if biosample['title']
    text_fields << biosample['Title'] if biosample['Title']
    text_fields << biosample['description'] if biosample['description']
    text_fields << biosample['Description'] if biosample['Description']

    # Add attribute values if present
    if biosample['attributes'].is_a?(Hash)
      biosample['attributes'].each_value do |value|
        text_fields << value.to_s if value
      end
    elsif biosample['Attributes'].is_a?(Hash)
      biosample['Attributes'].each_value do |value|
        text_fields << value.to_s if value
      end
    end

    text_fields.join(' ').strip
  end

  def print_summary
    log_message(:info, "\n" + "="*50)
    log_message(:info, "EXTRACTION SUMMARY")
    log_message(:info, "="*50)
    log_message(:info, "Total records found: #{@total_records}")
    log_message(:info, "Successfully processed: #{@processed_records}")
    log_message(:info, "Skipped records: #{@skipped_records}")
    log_message(:info, "  - JSON parse errors: #{@parse_errors}")
    log_message(:info, "  - Missing accession: #{@missing_accession_errors}")
    log_message(:info, "Output file: #{@output_file}")
    log_message(:info, "Log file: #{@log_file}")
    log_message(:info, "="*50)

    if @processed_records > 0
      log_message(:info, "Extraction completed successfully!")
    else
      log_message(:warn, "No records were successfully processed!")
    end
  end
end

# Command line argument parsing
def parse_arguments
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby bin/extract_biosample.rb INPUT_JSON [--outdir OUTDIR]"

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
    puts "Error: INPUT_JSON file is required"
    puts "Usage: ruby bin/extract_biosample.rb INPUT_JSON [--outdir OUTDIR]"
    exit 1
  end

  options[:input_file] = ARGV[0]
  options[:outdir] ||= '.'

  options
end

# Main execution
if __FILE__ == $0
  options = parse_arguments
  extractor = BioSampleExtractor.new(options[:input_file], options[:outdir])
  extractor.run
end
