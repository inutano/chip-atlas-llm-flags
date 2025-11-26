#!/usr/bin/env ruby

# extract_biosample.rb - Multi-format BioSample extraction script
#
# USAGE:
#   ruby bin/extract_biosample.rb INPUT_FILE [--outdir OUTDIR]
#
# DESCRIPTION:
#   This script processes input files in multiple formats and extracts structured
#   metadata for classification analysis. Supports both JSON BioSample arrays and
#   TSV experimentList.tab format.
#
# SUPPORTED FORMATS:
#   - JSON: Array of BioSample objects (original format)
#   - TSV: experimentList.tab format with columns:
#     Column 1: Experiment ID (used as id)
#     Column 9: Title
#     Column 10: Key=value pairs (semicolon separated, parsed into attributes)
#
# ARGUMENTS:
#   INPUT_FILE    Path to input file (JSON or TSV format)
#   --outdir      Output directory (optional, defaults to output directory)
#
# OUTPUT FILES:
#   - biosample_extracted_YYYYMMDD_HHMMSS.jsonl - Extracted records
#   - biosample_extracted_YYYYMMDD_HHMMSS.log    - Processing log file
#
# OUTPUT FORMAT:
#   Each line in the JSONL file contains a JSON object with extracted metadata
#   including id, title, description, organism, and attributes.
#
# EXAMPLES:
#   ruby bin/extract_biosample.rb data/biosamples.json
#   ruby bin/extract_biosample.rb data/experimentList.tab --outdir output/
#

require 'json'
require 'optparse'
require 'logger'
require 'time'
require 'fileutils'
require 'csv'

class BioSampleExtractor
  def initialize(input_file, output_dir = 'output')
    @input_file = input_file
    @base_output_dir = output_dir
    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    @output_dir = File.join(@base_output_dir, @timestamp)
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
    # Create timestamped output directory if it doesn't exist
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

    log(:info, "Reading input file: #{@input_file}")

    # Detect file format
    format = detect_file_format(@input_file)
    log(:info, "Detected format: #{format.upcase}")

    File.open(@output_file, 'w') do |output|
      case format
      when :json
        process_json_file(output)
      when :tsv
        process_tsv_file(output)
      else
        raise "Unsupported file format: #{format}"
      end
    end
  end

  def detect_file_format(file_path)
    # Check file extension first
    case File.extname(file_path).downcase
    when '.json'
      return :json
    when '.tab', '.tsv', '.txt'
      return :tsv
    end

    # Check content if extension is ambiguous
    first_line = File.open(file_path, 'r') { |f| f.readline.strip rescue "" }

    if first_line.start_with?('[') || first_line.start_with?('{')
      :json
    elsif first_line.include?("\t")
      :tsv
    else
      # Default to JSON for unknown formats
      log(:warn, "Unable to determine format from extension or content, defaulting to JSON")
      :json
    end
  end

  def process_tsv_file(output)
    log(:info, "Processing TSV format (experimentList.tab)")
    log(:info, "Column mapping: 1=ID, 9=Title, 10=Attributes")



    line_number = 0

    begin
      File.foreach(@input_file) do |line|
        line_number += 1
        @total_records += 1

        # Skip empty lines
        line = line.strip
        if line.empty?
          log(:warn, "Line #{line_number}: Empty line, skipping")
          @skipped_records += 1
          next
        end

        begin
          # Split by tabs, handling potential quoting issues
          columns = line.split("\t")

          # Extract data according to column specification (1-indexed in spec, 0-indexed in array)
          experiment_id = columns[0]&.strip   # Column 1
          title = columns[8]&.strip           # Column 9 (0-indexed = 8)
          attributes_str = columns[9]&.strip  # Column 10 (0-indexed = 9)

          # Validate experiment ID
          unless valid_experiment_id?(experiment_id)
            @skipped_records += 1
            @missing_accession_errors += 1
            log(:warn, "Line #{line_number}: Invalid or missing experiment ID '#{experiment_id}', skipping")
            next
          end

          # Parse attributes
          attributes = parse_key_value_pairs(attributes_str || '')

          # Create biosample record
          biosample_record = {
            'id' => experiment_id,
            'title' => title || '',
            'description' => '', # Not available in TSV format
            'organism' => '',    # Not available in TSV format
            'attributes' => attributes
          }

          # Write to output
          output.puts(JSON.generate(biosample_record))
          @processed_records += 1

          # Log progress every 1000 records
          if (@processed_records % 1000) == 0
            log(:info, "Processed #{@processed_records} records...")
          end

        rescue => e
          @parse_errors += 1
          @skipped_records += 1
          log(:warn, "Line #{line_number}: Error parsing line - #{e.message}")
          log(:warn, "Line content (first 100 chars): '#{line[0..99]}'") if line
          next
        end
      end

    rescue => e
      log(:error, "Error processing TSV file: #{e.message}")
      raise
    end
  end

  def parse_key_value_pairs(attributes_str)
    attributes = {}
    return attributes if attributes_str.nil? || attributes_str.empty?

    # Clean up potential quoting issues in the attributes string
    clean_str = attributes_str.gsub(/^"|"$/, '').gsub(/\\"|""/, '"')

    # Split by semicolon and parse key=value pairs
    clean_str.split(';').each do |pair|
      pair = pair.strip
      next if pair.empty?

      # Split on first '=' to handle values that contain '='
      key, value = pair.split('=', 2)
      next unless key && value

      key = key.strip
      value = value.strip

      # Clean up any remaining quote issues in key and value
      key = key.gsub(/^"|"$/, '').gsub(/\\"|""/, '"')
      value = value.gsub(/^"|"$/, '').gsub(/\\"|""/, '"')

      # Add to attributes if both key and value are non-empty
      if !key.empty? && !value.empty?
        attributes[key] = value
      end
    end

    attributes
  end

  def valid_experiment_id?(id)
    # For TSV format, we accept various experiment ID formats
    return false if id.nil? || id.empty?

    # Basic validation: non-empty, reasonable length, printable characters
    return false if id.length > 100  # Reasonable maximum length
    return false if id.match?(/[[:cntrl:]]/)  # No control characters

    true
  end

  def process_json_file(output)
    log(:info, "Processing JSON format (BioSample array)")

    begin
      json_content = File.read(@input_file)
      biosamples = JSON.parse(json_content)

      unless biosamples.is_a?(Array)
        raise "Input JSON must contain an array of BioSample objects"
      end

      @total_records = biosamples.length
      log(:info, "Found #{@total_records} records to process")

      biosamples.each_with_index do |biosample, index|
        process_json_biosample(biosample, index, output)
      end

    rescue JSON::ParserError => e
      log(:error, "Failed to parse JSON file: #{e.message}")
      raise
    end
  end

  def process_json_biosample(biosample, index, output)
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
    opts.banner = "Usage: ruby bin/extract_biosample.rb INPUT_FILE [--outdir OUTDIR]"

    opts.on("--outdir OUTDIR", "Output directory (default: output directory)") do |outdir|
      options[:outdir] = outdir
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts ""
      puts "Supported formats:"
      puts "  JSON: Array of BioSample objects"
      puts "  TSV:  experimentList.tab with columns 1=ID, 9=Title, 10=Attributes"
      exit
    end
  end.parse!

  # Validate required argument
  if ARGV.empty?
    puts "Error: INPUT_FILE is required"
    puts "Usage: ruby bin/extract_biosample.rb INPUT_FILE [--outdir OUTDIR]"
    exit 1
  end

  options[:input_file] = ARGV[0]
  options[:outdir] ||= 'output'

  options
end

# Main execution
if __FILE__ == $0
  options = parse_arguments
  extractor = BioSampleExtractor.new(options[:input_file], options[:outdir])
  extractor.run
end
