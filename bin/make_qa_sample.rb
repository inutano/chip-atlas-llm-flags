#!/usr/bin/env ruby

# make_qa_sample.rb - Creates QA sample by joining extracted data with predictions
#
# USAGE:
#   ruby bin/make_qa_sample.rb EXTRACTED_JSONL NORMALIZED_JSONL [OPTIONS]
#
# DESCRIPTION:
#   This script joins extracted BioSample JSONL files with normalized prediction
#   results to create a TSV file suitable for quality assessment and manual
#   review of LLM predictions.
#
# ARGUMENTS:
#   EXTRACTED_JSONL    Path to extracted BioSample JSONL file
#   NORMALIZED_JSONL   Path to normalized predictions JSONL file
#   --n N             Number of samples for random sampling (optional)
#   --outdir          Output directory (default: current directory)
#
# OUTPUT:
#   TSV file with columns: id, title, description, organism, attr_disease_like,
#   attr_treatments_like, attr_gene_mod_like, disease, treatments, gene-modification
#
# EXAMPLES:
#   ruby bin/make_qa_sample.rb extracted.jsonl normalized.jsonl --n 200
#   ruby bin/make_qa_sample.rb data.jsonl predictions.jsonl --outdir output/
#

require 'json'
require 'optparse'
require 'time'
require 'fileutils'
require 'csv'
require 'logger'

class QASampleMaker
  def initialize(extracted_file, normalized_file, options = {})
    @extracted_file = extracted_file
    @normalized_file = normalized_file
    @sample_size = options[:sample_size]
    @base_output_dir = options[:output_dir] || '.'

    # Use the same directory as the input files if they're in an output directory
    @output_dir = detect_output_directory(@normalized_file, @base_output_dir)
    @output_file = File.join(@output_dir, "qa_sample.tsv")
    @log_file = File.join(@output_dir, "qa_sample.log")

    # Statistics
    @extracted_records = 0
    @prediction_records = 0
    @matched_records = 0
    @final_sample_size = 0

    # Data storage
    @extracted_data = {}
    @predictions = {}

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

    log(:info, "=== QA SAMPLE START ===")
    log(:info, "Starting QA sample creation")
    log(:info, "Extracted file: #{@extracted_file}")
    log(:info, "Predictions file: #{@normalized_file}")
    log(:info, "Output file: #{@output_file}")
    log(:info, "Sample size: #{@sample_size || 'all records'}")

    start_time = Time.now

    # Load data
    load_extracted_data
    load_predictions

    # Join and create sample
    create_qa_sample

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
    unless File.exist?(@extracted_file)
      raise "Extracted file not found: #{@extracted_file}"
    end

    unless File.exist?(@normalized_file)
      raise "Predictions file not found: #{@normalized_file}"
    end
  end

  def load_extracted_data
    log(:info, "Loading extracted BioSample data...")

    File.foreach(@extracted_file) do |line|
      line = line.strip
      next if line.empty?

      begin
        record = JSON.parse(line)
        if record['id']
          @extracted_data[record['id']] = record
          @extracted_records += 1
        end
      rescue JSON::ParserError => e
        log(:warn, "Invalid JSON in extracted file: #{e.message}")
      end
    end

    log(:info, "Loaded #{@extracted_records} extracted records")
  end

  def load_predictions
    log(:info, "Loading prediction data...")

    File.foreach(@normalized_file) do |line|
      line = line.strip
      next if line.empty?

      begin
        record = JSON.parse(line)
        if record['id']
          @predictions[record['id']] = record
          @prediction_records += 1
        end
      rescue JSON::ParserError => e
        log(:warn, "Invalid JSON in predictions file: #{e.message}")
      end
    end

    log(:info, "Loaded #{@prediction_records} prediction records")
  end

  def create_qa_sample
    log(:info, "Creating QA sample...")

    # Find matching records
    matched_records = []

    @predictions.each do |id, prediction|
      if @extracted_data.has_key?(id)
        extracted = @extracted_data[id]

        # Create joined record
        qa_record = create_qa_record(extracted, prediction)
        matched_records << qa_record
        @matched_records += 1
      end
    end

    log(:info, "Found #{@matched_records} records with both extraction and prediction data")

    # Sample if requested
    if @sample_size && @sample_size < matched_records.length
      log(:info, "Randomly sampling #{@sample_size} records from #{matched_records.length}")
      matched_records = matched_records.sample(@sample_size)
    end

    @final_sample_size = matched_records.length

    # Write TSV output
    write_tsv_output(matched_records)
  end

  def create_qa_record(extracted, prediction)
    # Extract basic fields
    id = extracted['id']
    title = extracted['title'] || ''
    description = extracted['description'] || ''
    organism = extracted['organism'] || ''

    # Extract attribute-based indicators
    attributes = extracted['attributes'] || {}
    attr_disease_like = extract_disease_like_attributes(attributes)
    attr_treatments_like = extract_treatments_like_attributes(attributes)
    attr_gene_mod_like = extract_gene_mod_like_attributes(attributes)

    # Truncate long attribute strings
    attr_disease_like = truncate_text(attr_disease_like, 200)
    attr_treatments_like = truncate_text(attr_treatments_like, 200)
    attr_gene_mod_like = truncate_text(attr_gene_mod_like, 200)

    # Get predictions
    disease = prediction['disease']
    treatments = prediction['treatments']
    gene_modification = prediction['gene-modification']

    {
      id: id,
      title: title,
      description: description,
      organism: organism,
      attr_disease_like: attr_disease_like,
      attr_treatments_like: attr_treatments_like,
      attr_gene_mod_like: attr_gene_mod_like,
      disease: disease,
      treatments: treatments,
      gene_modification: gene_modification
    }
  end

  def extract_disease_like_attributes(attributes)
    disease_keywords = %w[
      disease condition disorder syndrome cancer tumor malignant benign
      patient clinical pathology diagnosis therapeutic treatment therapy
      infection inflammatory autoimmune metabolic genetic hereditary
      diabetes hypertension obesity leukemia lymphoma carcinoma sarcoma
      adenoma melanoma glioma neuroblastoma hepatoma
    ]

    matching_attrs = []
    attributes.each do |key, value|
      key_str = key.to_s.downcase
      value_str = value.to_s.downcase

      if disease_keywords.any? { |keyword| key_str.include?(keyword) || value_str.include?(keyword) }
        matching_attrs << "#{key}: #{value}"
      end
    end

    matching_attrs.join('; ')
  end

  def extract_treatments_like_attributes(attributes)
    treatment_keywords = %w[
      treatment treated drug medication compound chemical reagent
      therapy therapeutic intervention exposure stimulation
      doxorubicin metformin aspirin antibiotic antiviral
      chemotherapy radiotherapy immunotherapy
      dose dosage concentration time hours days
      control untreated vehicle dmso
    ]

    matching_attrs = []
    attributes.each do |key, value|
      key_str = key.to_s.downcase
      value_str = value.to_s.downcase

      if treatment_keywords.any? { |keyword| key_str.include?(keyword) || value_str.include?(keyword) }
        matching_attrs << "#{key}: #{value}"
      end
    end

    matching_attrs.join('; ')
  end

  def extract_gene_mod_like_attributes(attributes)
    gene_mod_keywords = %w[
      crispr knockout overexpression transgenic transfection
      plasmid vector construct gene genetic modification
      ko kd shrna sirna grna cas9 cas12
      mutant mutation variant allele genotype
      gfp flag tagged fusion reporter
      stable transient expression
    ]

    matching_attrs = []
    attributes.each do |key, value|
      key_str = key.to_s.downcase
      value_str = value.to_s.downcase

      if gene_mod_keywords.any? { |keyword| key_str.include?(keyword) || value_str.include?(keyword) }
        matching_attrs << "#{key}: #{value}"
      end
    end

    matching_attrs.join('; ')
  end

  def truncate_text(text, max_length)
    return text if text.length <= max_length
    text[0..max_length-4] + "..."
  end

  def write_tsv_output(records)
    log(:info, "Writing TSV output with #{records.length} records...")

    headers = [
      'id', 'title', 'description', 'organism',
      'attr_disease_like', 'attr_treatments_like', 'attr_gene_mod_like',
      'disease', 'treatments', 'gene-modification'
    ]

    CSV.open(@output_file, 'w', col_sep: "\t") do |tsv|
      tsv << headers

      records.each do |record|
        row = [
          record[:id],
          record[:title],
          record[:description],
          record[:organism],
          record[:attr_disease_like],
          record[:attr_treatments_like],
          record[:attr_gene_mod_like],
          record[:disease],
          record[:treatments],
          record[:gene_modification]
        ]
        tsv << row
      end
    end
  end

  def print_summary(total_time)
    skipped_records = @extracted_records + @prediction_records - @matched_records
    failed_records = 0

    log(:info, "=== QA SAMPLE SUMMARY ===")
    log(:info, "Total processing time: #{total_time.round(2)} seconds")
    log(:info, "Extracted records loaded: #{@extracted_records}")
    log(:info, "Prediction records loaded: #{@prediction_records}")
    log(:info, "Successfully processed: #{@final_sample_size}")
    log(:info, "Skipped records: #{skipped_records}")
    log(:info, "Failed records: #{failed_records}")
    log(:info, "Matched records: #{@matched_records}")
    log(:info, "Output file: #{@output_file}")
    log(:info, "Log file: #{@log_file}")

    if @final_sample_size > 0
      log(:info, "=== QA SAMPLE END ===")
    else
      log(:warn, "=== QA SAMPLE END === (No matching records found)")
    end
  end
end

def parse_arguments
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby bin/make_qa_sample.rb EXTRACTED_JSONL NORMALIZED_JSONL [OPTIONS]"

    opts.on("--n N", Integer, "Number of samples for random sampling") do |n|
      options[:sample_size] = n
    end

    opts.on("--outdir DIR", "Output directory (default: current directory)") do |dir|
      options[:output_dir] = dir
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  if ARGV.length < 2
    puts "Error: Both EXTRACTED_JSONL and NORMALIZED_JSONL files are required"
    puts "Usage: ruby bin/make_qa_sample.rb EXTRACTED_JSONL NORMALIZED_JSONL [OPTIONS]"
    exit 1
  end

  options[:extracted_file] = ARGV[0]
  options[:normalized_file] = ARGV[1]

  options
end

# Main execution
if __FILE__ == $0
  begin
    options = parse_arguments
    qa_maker = QASampleMaker.new(options[:extracted_file], options[:normalized_file], options)
    qa_maker.run
  rescue => e
    puts "FATAL ERROR: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end
