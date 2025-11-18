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
#   metadata including id, title, description, organism, and attributes.
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
require 'optparse'
require 'logger'
require 'time'
require 'fileutils'

class BioSampleExtractor
  def initialize(input_file, output_dir = '.')
    @input_file = input_file
    @base_output_dir = output_dir
    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    @output_dir = File.join(@base_output_dir, "output", @timestamp)
    @output_file = File.join(@output_dir, "biosample_extracted.jsonl")
    @log_file = File.join(@output_dir, "biosample_extracted.log")

    # Initialize counters for summary
    @total_records = 0
    @processed_records = 0
    @skipped_records = 0
    @parse_errors = 0
    @missing_accession_errors = 0

    setup_logger
  end

  def run
    log(:info, "=== EXTRACTION START ===")
    log(:info, "Starting BioSample extraction from #{@input_file}")
    log(:info, "Output file: #{@output_file}")
    log(:info, "Log file: #{@log_file}")

    begin
      process_input_file
      print_summary
    rescue => e
      log(:error, "Fatal error during processing: #{e.message}")
      log(:error, e.backtrace.join("\n"))
      exit 1
    end
  end

  private

  def setup_logger
    # Create output directory if it doesn't exist
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

  def process_input_file
    unless File.exist?(@input_file)
      raise "Input file not found: #{@input_file}"
    end

    # Create output directory
    FileUtils.mkdir_p(@output_dir)

    log(:info, "Reading input file: #{@input_file}")

    File.open(@output_file, 'w') do |output|
      # Detect file format and process accordingly
      if jsonl_format?(@input_file)
        log(:info, "Detected JSONL format, processing line by line")
        process_jsonl_file(output)
      else
        log(:info, "Detected JSON array format, processing as array")
        process_json_array_file(output)
      end
    end
  end

  def jsonl_format?(file_path)
    # Read first line and check if it's a standalone JSON object
    first_line = File.open(file_path, 'r') { |f| f.readline.strip rescue "" }
    return false if first_line.empty?

    begin
      JSON.parse(first_line)
      # If we can parse the first line as JSON, check if the whole file is a JSON array
      full_content = File.read(file_path).strip
      return !full_content.start_with?('[')
    rescue JSON::ParserError
      return false
    end
  end

  def process_json_array_file(output)
    begin
      json_content = File.read(@input_file)
      biosamples = JSON.parse(json_content)

      unless biosamples.is_a?(Array)
        raise "Input JSON must contain an array of BioSample objects"
      end

      @total_records = biosamples.length
      log(:info, "Found #{@total_records} records to process")

      biosamples.each_with_index do |biosample, index|
        process_biosample(biosample, index, output)
      end

    rescue JSON::ParserError => e
      log(:error, "Failed to parse JSON file: #{e.message}")
      raise
    end
  end

  def process_jsonl_file(output)
    records = []
    line_number = 0

    File.foreach(@input_file) do |line|
      line_number += 1
      line = line.strip
      next if line.empty?

      begin
        record = JSON.parse(line)
        transformed_record = transform_biosample_structure(record)
        records << transformed_record
      rescue JSON::ParserError => e
        log(:warn, "Skipping line #{line_number}: Invalid JSON - #{e.message}")
        next
      end
    end

    @total_records = records.length
    log(:info, "Found #{@total_records} records to process")

    records.each_with_index do |biosample, index|
      process_biosample(biosample, index, output)
    end
  end

  def transform_biosample_structure(record)
    # Handle biosample_id + entry structure (your data format)
    if record["biosample_id"] && record["entry"]
      log(:debug, "Transforming biosample_id + entry structure for record: #{record["biosample_id"]}")

      # Start with entry data
      transformed = record["entry"].dup

      # Map biosample_id to accession
      transformed["accession"] = record["biosample_id"]

      # Preserve other top-level fields (like srx) as attributes
      record.each do |key, value|
        next if key == "biosample_id" || key == "entry"
        transformed["additional_#{key}"] = value
      end

      return transformed
    end

    # Handle flat structure with biosample_id field
    if record["biosample_id"] && !record["accession"]
      log(:debug, "Mapping biosample_id to accession for record: #{record["biosample_id"]}")
      record = record.dup
      record["accession"] = record["biosample_id"]
      record.delete("biosample_id")
      return record
    end

    # Return as-is for standard structures
    record
  end

  def process_biosample(biosample, index, output)
    begin
      # Validate that biosample is a hash
      unless biosample.is_a?(Hash)
        @skipped_records += 1
        @parse_errors += 1
        log(:warn, "Record #{index + 1}: Not a valid object, skipping")
        return
      end

      # Check for required accession field
      id = extract_biosample_id(biosample)
      unless id
        @skipped_records += 1
        @missing_accession_errors += 1
        log(:warn, "Record #{index + 1}: No valid BioSample accession found, skipping")
        return
      end

      # Extract and structure the biosample data
      extracted_data = extract_biosample_data(biosample, id)

      # Write to output file
      output.puts(JSON.generate(extracted_data))
      @processed_records += 1

      # Log progress every 1000 records
      if (@processed_records % 1000) == 0
        log(:info, "Processed #{@processed_records} records...")
      end

    rescue => e
      @skipped_records += 1
      @parse_errors += 1
      log(:warn, "Record #{index + 1}: Error processing - #{e.message}")
    end
  end

  def extract_biosample_id(biosample)
    # Look for BioSample accession in various possible fields
    possible_id_fields = [
      'accession', 'Accession', 'id', 'Id', 'ID',
      'biosample_accession', 'BioSample_accession'
    ]

    possible_id_fields.each do |field|
      if biosample[field]
        id = biosample[field].to_s.strip
        # Check if it matches BioSample accession pattern (SAMN*, SAMD*, SAMEA*)
        if id.match?(/^SAM[NDE][A-Z]?\d+$/)
          return id
        end
      end
    end

    nil
  end

  def extract_title_or_name(biosample)
    # Look for title, name, or sample_name (first found)
    possible_name_fields = [
      'title', 'Title', 'name', 'Name', 'sample_name', 'Sample_name',
      'sample_title', 'Sample_title', 'sampleName', 'SampleName'
    ]

    possible_name_fields.each do |field|
      if biosample[field] && !biosample[field].to_s.strip.empty?
        return biosample[field].to_s.strip
      end
    end

    ''
  end

  def extract_description(biosample)
    # Look for description field
    possible_desc_fields = ['description', 'Description', 'desc', 'Desc']

    possible_desc_fields.each do |field|
      if biosample[field] && !biosample[field].to_s.strip.empty?
        return biosample[field].to_s.strip
      end
    end

    ''
  end

  def extract_organism(biosample)
    # Look for organism information and combine scientific name and TaxID if both exist
    organism_info = []

    # Look for scientific name
    scientific_name_fields = [
      'organism', 'Organism', 'scientific_name', 'Scientific_name',
      'species', 'Species', 'organism_name', 'Organism_name'
    ]

    scientific_name = nil
    scientific_name_fields.each do |field|
      if biosample[field] && !biosample[field].to_s.strip.empty?
        scientific_name = biosample[field].to_s.strip
        break
      end
    end

    # Look for TaxID
    taxid_fields = [
      'taxid', 'TaxID', 'tax_id', 'Tax_ID', 'taxonomy_id', 'Taxonomy_ID',
      'ncbi_taxid', 'NCBI_TaxID'
    ]

    taxid = nil
    taxid_fields.each do |field|
      if biosample[field] && !biosample[field].to_s.strip.empty?
        taxid = biosample[field].to_s.strip
        break
      end
    end

    # Combine scientific name and TaxID if both exist
    if scientific_name && taxid
      "#{scientific_name} (TaxID: #{taxid})"
    elsif scientific_name
      scientific_name
    elsif taxid
      "TaxID: #{taxid}"
    else
      ''
    end
  end

  def extract_attributes(biosample)
    # Extract attributes, preserving original key spelling
    attributes = {}

    # Look for attributes in common field names
    attr_fields = ['attributes', 'Attributes', 'attr', 'Attr']

    attr_fields.each do |field|
      if biosample[field].is_a?(Hash)
        biosample[field].each do |key, value|
          # Skip if value is nil or empty
          next if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          attributes[key] = value
        end
        break
      end
    end

    # Also include other fields that aren't metadata fields, excluding unwanted ones
    excluded_fields = [
      'accession', 'Accession', 'id', 'Id', 'ID', 'biosample_accession', 'BioSample_accession',
      'title', 'Title', 'name', 'Name', 'sample_name', 'Sample_name', 'sample_title', 'Sample_title',
      'sampleName', 'SampleName', 'description', 'Description', 'desc', 'Desc',
      'organism', 'Organism', 'scientific_name', 'Scientific_name', 'species', 'Species',
      'organism_name', 'Organism_name', 'taxid', 'TaxID', 'tax_id', 'Tax_ID',
      'taxonomy_id', 'Taxonomy_ID', 'ncbi_taxid', 'NCBI_TaxID',
      'attributes', 'Attributes', 'attr', 'Attr',
      'links', 'Links', 'externalReferences', 'ExternalReferences', 'external_references',
      'dates', 'Dates', 'date', 'Date', 'created', 'Created', 'updated', 'Updated',
      'submission_date', 'Submission_date', 'publication_date', 'Publication_date'
    ]

    biosample.each do |key, value|
      # Skip excluded fields and fields that start with common date/link patterns
      next if excluded_fields.include?(key)
      next if key.to_s.downcase.include?('date')
      next if key.to_s.downcase.include?('link')
      next if key.to_s.downcase.include?('reference')
      next if key.to_s.downcase.include?('url')
      next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

      # Only include simple values (strings, numbers, booleans)
      if value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
        attributes[key] = value
      end
    end

    attributes
  end

  def extract_biosample_data(biosample, id)
    {
      id: id,
      title: extract_title_or_name(biosample),
      description: extract_description(biosample),
      organism: extract_organism(biosample),
      attributes: extract_attributes(biosample)
    }
  end

  def print_summary
    log(:info, "=== EXTRACTION SUMMARY ===")
    log(:info, "Total records found: #{@total_records}")
    log(:info, "Successfully processed: #{@processed_records}")
    log(:info, "Skipped records: #{@skipped_records}")
    log(:info, "Failed records: #{@parse_errors}")
    log(:info, "  - JSON parse errors: #{@parse_errors}")
    log(:info, "  - Missing accession: #{@missing_accession_errors}")
    log(:info, "Output file: #{@output_file}")
    log(:info, "Log file: #{@log_file}")

    if @processed_records > 0
      log(:info, "=== EXTRACTION END ===")
    else
      log(:warn, "=== EXTRACTION END === (No records processed)")
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
