#!/usr/bin/env ruby

# run_llama_local.rb - Local LLM inference for BioSample classification
#
# USAGE:
#   ruby bin/run_llama_local.rb INPUT_JSONL --model MODEL_PATH [OPTIONS]
#
# DESCRIPTION:
#   This script processes extracted BioSample JSONL files using a local LLM
#   (llama.cpp or MLC) to classify samples into disease, treatments, and
#   gene-modification flags based on the prompt template in PROMPT.md.
#
# REQUIRED ARGUMENTS:
#   INPUT_JSONL   Path to extracted BioSample JSONL file
#   --model       Path to GGUF model file
#
# OPTIONS:
#   --ctx         Context window size (default: 4096)
#   --batch       Batch size (default: 8)
#   --outdir      Output directory (default: current directory)
#   --binary      Path to llama.cpp binary (default: llama-cli)
#
# OUTPUT:
#   Creates timestamped JSONL file with predictions and metadata
#
# EXAMPLES:
#   ruby bin/run_llama_local.rb input.jsonl --model /path/to/model.gguf
#   ruby bin/run_llama_local.rb input.jsonl --model model.gguf --ctx 8192 --batch 16
#

require 'json'
require 'optparse'
require 'open3'
require 'time'
require 'fileutils'
require 'tmpdir'

class LlamaLocalRunner
  def initialize(options)
    @input_file = options[:input_file]
    @model_path = options[:model_path]
    @ctx_size = options[:ctx_size] || 4096
    @batch_size = options[:batch_size] || 8
    @output_dir = options[:output_dir] || '.'
    @binary_path = options[:binary_path] || 'llama-cli'

    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    @output_file = File.join(@output_dir, "biosample_predictions_#{@timestamp}.jsonl")
    @log_file = File.join(@output_dir, "biosample_predictions_#{@timestamp}.log")

    # Statistics
    @total_processed = 0
    @total_failed = 0
    @total_runtime_ms = 0
    @retry_counts = Hash.new(0)
    @skipped_records = 0

    setup_logging
    load_prompt_template
  end

  def run
    validate_inputs

    log(:info, "=== INFERENCE START ===")
    log(:info, "Starting LLM inference on #{@input_file}")
    log(:info, "Model: #{@model_path}")
    log(:info, "Output: #{@output_file}")
    log(:info, "Context size: #{@ctx_size}, Batch size: #{@batch_size}")

    start_time = Time.now

    File.open(@output_file, 'w') do |output|
      File.foreach(@input_file) do |line|
        line = line.strip
        next if line.empty?

        process_line(line, output)
      end
    end

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

  def load_prompt_template
    prompt_file = File.join(__dir__, '..', 'PROMPT.md')
    unless File.exist?(prompt_file)
      raise "PROMPT.md not found at #{prompt_file}"
    end

    content = File.read(prompt_file)
    # Extract the prompt template between triple backticks after "Prompt Template"
    template_match = content.match(/## Prompt Template\s*```[^\n]*\n(.*?)\n```/m)
    unless template_match
      raise "Could not find prompt template in PROMPT.md"
    end

    @prompt_template = template_match[1]
  end

  def validate_inputs
    unless File.exist?(@input_file)
      raise "Input file not found: #{@input_file}"
    end

    unless File.exist?(@model_path)
      raise "Model file not found: #{@model_path}"
    end

    # Test if binary is available
    stdout, stderr, status = Open3.capture3("#{@binary_path} --help")
    unless status.success?
      raise "LLM binary not found or not working: #{@binary_path}"
    end
  end

  def process_line(line, output)
    begin
      record = JSON.parse(line)
      result = classify_sample(record)
      output.puts JSON.generate(result)
      @total_processed += 1

      if (@total_processed % 10) == 0
        log(:info, "Processed #{@total_processed} samples...")
      end

    rescue JSON::ParserError => e
      log(:error, "Invalid JSON in input line: #{e.message}")
      @total_failed += 1
    rescue => e
      log(:error, "Failed to process record: #{e.message}")
      @total_failed += 1
    end
  end

  def classify_sample(record)
    id = record['id']
    prompt = build_prompt(record)

    start_time = Time.now
    prediction, retries, error_flag = run_llm_inference(prompt)
    runtime_ms = ((Time.now - start_time) * 1000).to_i

    @total_runtime_ms += runtime_ms
    @retry_counts[retries] += 1

    result = {
      'id' => id,
      'prediction' => prediction,
      'runtime_ms' => runtime_ms,
      'retries' => retries
    }

    result['flag'] = error_flag if error_flag
    result
  end

  def build_prompt(record)
    title = record['title'] || ''
    description = record['description'] || ''
    organism = record['organism'] || ''
    attributes = record['attributes'] || {}

    # Build attributes section
    attrs_text = attributes.map { |k, v| "#{k}: #{v}" }.join("\n")

    # Replace template variables
    prompt = @prompt_template.dup
    prompt.gsub!('{TITLE_OR_NAME}', title)
    prompt.gsub!('{DESCRIPTION}', description)
    prompt.gsub!('{ORGANISM_OR_TAXID}', organism)
    prompt.gsub!('{KEY1}: {VAL1}\n{KEY2}: {VAL2}\n...', attrs_text)

    prompt
  end

  def run_llm_inference(prompt)
    retries = 0
    max_retries = 3

    while retries <= max_retries
      begin
        prediction = call_llm(prompt)

        # Validate JSON response
        parsed = JSON.parse(prediction)

        # Ensure it has the required structure
        if parsed.is_a?(Hash) &&
           parsed.has_key?('disease') &&
           parsed.has_key?('treatments') &&
           parsed.has_key?('gene-modification') &&
           [true, false].include?(parsed['disease']) &&
           [true, false].include?(parsed['treatments']) &&
           [true, false].include?(parsed['gene-modification'])

          return [parsed, retries, nil]
        else
          raise "Invalid prediction structure: #{prediction}"
        end

      rescue JSON::ParserError, StandardError => e
        retries += 1
        if retries <= max_retries
          log(:warn, "Retry #{retries}/#{max_retries} due to error: #{e.message}")
        end
      end
    end

    # Failed all retries, return default
    default_prediction = {
      'disease' => false,
      'treatments' => false,
      'gene-modification' => false
    }

    [default_prediction, max_retries, 'invalid_json']
  end

  def call_llm(prompt)
    # Prepare temporary prompt file
    temp_dir = Dir.tmpdir
    prompt_file = File.join(temp_dir, "llm_prompt_#{Process.pid}_#{rand(10000)}.txt")
    File.write(prompt_file, prompt)

    # Build llama.cpp command
    cmd = [
      @binary_path,
      '--model', @model_path,
      '--ctx-size', @ctx_size.to_s,
      '--batch-size', @batch_size.to_s,
      '--temp', '0',
      '--top-p', '0.9',
      '--n-predict', '64',
      '--prompt-file', prompt_file,
      '--no-display-prompt'
    ]

    # Execute command
    stdout, stderr, status = Open3.capture3(*cmd)

    # Debug logging
    log "DEBUG: Command: #{cmd.join(' ')}" if ENV['DEBUG']
    log "DEBUG: stdout: #{stdout}" if ENV['DEBUG'] && !stdout.empty?
    log "DEBUG: stderr: #{stderr}" if ENV['DEBUG'] && !stderr.empty?

    # Clean up prompt file
    File.unlink(prompt_file) if File.exist?(prompt_file)

    unless status.success?
      raise "LLM execution failed: #{stderr}"
    end

    # Extract JSON from output (remove any extra text)
    response = stdout.strip

    # Try to find JSON in the response
    json_match = response.match(/\{.*\}/m)
    if json_match
      json_match[0]
    else
      response
    end
  end

  def print_summary(total_time)
    avg_runtime = @total_processed > 0 ? @total_runtime_ms.to_f / @total_processed : 0

    log(:info, "=== INFERENCE SUMMARY ===")
    log(:info, "Total processing time: #{total_time.round(2)} seconds")
    log(:info, "Successfully processed: #{@total_processed}")
    log(:info, "Skipped records: #{@skipped_records}")
    log(:info, "Failed records: #{@total_failed}")
    log(:info, "Average runtime per sample: #{avg_runtime.round(2)} ms")
    log(:info, "Retry distribution:")
    (0..3).each do |retry_count|
      count = @retry_counts[retry_count]
      percentage = @total_processed > 0 ? (count.to_f / @total_processed * 100).round(1) : 0
      log(:info, "  #{retry_count} retries: #{count} samples (#{percentage}%)")
    end
    log(:info, "Output file: #{@output_file}")
    log(:info, "Log file: #{@log_file}")

    if @total_processed > 0
      log(:info, "=== INFERENCE END ===")
    else
      log(:warn, "=== INFERENCE END === (No records processed)")
    end
  end
end

def parse_arguments
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby bin/run_llama_local.rb INPUT_JSONL --model MODEL_PATH [OPTIONS]"

    opts.on("--model PATH", "Path to GGUF model file (required)") do |path|
      options[:model_path] = path
    end

    opts.on("--ctx SIZE", Integer, "Context window size (default: 4096)") do |size|
      options[:ctx_size] = size
    end

    opts.on("--batch SIZE", Integer, "Batch size (default: 8)") do |size|
      options[:batch_size] = size
    end

    opts.on("--outdir DIR", "Output directory (default: current directory)") do |dir|
      options[:output_dir] = dir
    end

    opts.on("--binary PATH", "Path to llama.cpp binary (default: llama-cli)") do |path|
      options[:binary_path] = path
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "ERROR: INPUT_JSONL file is required"
    puts "Usage: ruby bin/run_llama_local.rb INPUT_JSONL --model MODEL_PATH [OPTIONS]"
    exit 1
  end

  unless options[:model_path]
    puts "ERROR: --model option is required"
    exit 1
  end

  options[:input_file] = ARGV[0]
  options
end

# Main execution
if __FILE__ == $0
  begin
    options = parse_arguments
    runner = LlamaLocalRunner.new(options)
    runner.run
  rescue => e
    puts "FATAL ERROR: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end
