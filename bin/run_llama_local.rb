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
require 'logger'

class LlamaLocalRunner
  def initialize(options)
    @input_file = options[:input_file]
    @model_path = options[:model_path]
    @ctx_size = options[:ctx_size] || 4096
    @batch_size = options[:batch_size] || 8
    @base_output_dir = options[:output_dir] || '.'
    @binary_path = options[:binary_path] || '~/repos/llama.cpp/build/bin/llama-cli'

    # Grammar enforcement settings (enabled by default)
    @use_grammar = options.fetch(:use_grammar, true)
    @grammar_file = options[:grammar_file]
    @llama_cpp_path = options[:llama_cpp_path] || detect_llama_cpp_path

    # Normalize base output directory
    @base_output_dir = normalize_base_output_dir(@base_output_dir)

    # Try to detect existing timestamped directory from input file path
    @output_dir = detect_output_directory(@input_file, @base_output_dir)
    @output_file = File.join(@output_dir, "biosample_predictions.jsonl")
    @log_file = File.join(@output_dir, "biosample_predictions.log")

    # Statistics
    @total_processed = 0
    @total_failed = 0
    @total_runtime_ms = 0
    @retry_counts = Hash.new(0)
    @skipped_records = 0
    @individual_runtimes = []

    setup_logging
    setup_grammar
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

  def detect_output_directory(input_file, base_output_dir)
    # Try to extract timestamp from input file path
    if input_file =~ /output\/(\d{8}_\d{6})\//
      timestamp_dir = $1
      output_dir = File.join(base_output_dir, "output", timestamp_dir)
      return output_dir if Dir.exist?(output_dir)
    end

    # If input file is in an output directory, use that
    input_dir = File.dirname(input_file)
    if input_dir =~ /output\/(\d{8}_\d{6})$/
      return input_dir
    end

    # Fallback: create new timestamped directory
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    output_dir = File.join(base_output_dir, timestamp)
    FileUtils.mkdir_p(output_dir)
    output_dir
  end

  def normalize_base_output_dir(base_dir)
    # If base_dir is current directory, use the 'output' subdirectory
    if base_dir == '.' || base_dir == './'
      return 'output'
    end
    base_dir
  end

  def setup_logging
    FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)

    # Setup dual logger (STDOUT + file)
    @logger = Logger.new(MultiIO.new(STDOUT, File.open(@log_file, 'w')))
    @logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.iso8601} [#{severity}] #{msg}\n"
    end

    # Grammar status will be logged after setup
    @grammar_status_logged = false
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
    binary_path = File.expand_path(@binary_path)
    stdout, stderr, status = Open3.capture3("#{binary_path} --help")
    unless status.success?
      raise "LLM binary not found or not working: #{binary_path}"
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
    @individual_runtimes << runtime_ms
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
    content = @prompt_template.dup
    content.gsub!('{TITLE_OR_NAME}', title)
    content.gsub!('{DESCRIPTION}', description)
    content.gsub!('{ORGANISM_OR_TAXID}', organism)
    # Replace the template pattern with actual newlines
    content.gsub!(/\{KEY1\}: \{VAL1\}\n\{KEY2\}: \{VAL2\}\n\.\.\./, attrs_text)

    # Use simpler prompt format for better grammar compatibility
    simple_prompt = "#{content}\n\nJSON response:"

    simple_prompt
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
          error_msg = "Invalid prediction structure: #{prediction}"
          error_msg += " (Grammar #{@use_grammar ? 'enabled' : 'disabled'})"
          raise error_msg
        end

      rescue JSON::ParserError, StandardError => e
        retries += 1
        error_msg = "#{e.message} (Grammar #{@use_grammar ? 'enabled' : 'disabled'})"
        if retries <= max_retries
          log(:warn, "Retry #{retries}/#{max_retries} due to error: #{error_msg}")
        else
          log(:error, "Max retries exceeded: #{error_msg}")
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

    # Debug: preserve prompt file if DEBUG is set
    if ENV['DEBUG']
      debug_prompt_file = File.join(@output_dir, "debug_prompt_#{Time.now.strftime('%H%M%S')}.txt")
      FileUtils.cp(prompt_file, debug_prompt_file)
      log(:debug, "DEBUG: Prompt saved to #{debug_prompt_file}")
    end

    # Build llama.cpp command
    binary_path = File.expand_path(@binary_path)
    cmd = [
      binary_path,
      '--model', @model_path,
      '--ctx-size', @ctx_size.to_s,
      '--batch-size', @batch_size.to_s,
      '--temp', '0',
      '--top-p', '0.9',
      '--n-predict', '64',
      '--file', prompt_file,
      '--no-display-prompt',
      '--no-conversation'
    ]

    # Add grammar file by default (if available)
    if @use_grammar && @grammar_file && File.exist?(@grammar_file)
      cmd += ['--grammar-file', @grammar_file]
      log(:debug, "Using grammar file: #{@grammar_file}") if ENV['DEBUG']
    end

    # Execute command
    stdout, stderr, status = Open3.capture3(*cmd)

    # Debug logging
    log(:debug, "DEBUG: Command: #{cmd.join(' ')}") if ENV['DEBUG']
    log(:debug, "DEBUG: stdout: #{stdout}") if ENV['DEBUG'] && !stdout.empty?
    log(:debug, "DEBUG: stderr: #{stderr}") if ENV['DEBUG'] && !stderr.empty?

    # Clean up prompt file
    File.unlink(prompt_file) if File.exist?(prompt_file)

    unless status.success?
      raise "LLM execution failed: #{stderr}"
    end

    # Extract JSON from output (remove any extra text)
    response = stdout.strip

    # Remove common llama.cpp output patterns
    response = response.gsub(/^system_info:.*$/m, '')
    response = response.gsub(/^main:.*$/m, '')
    response = response.gsub(/^sampler.*$/m, '')
    response = response.gsub(/^generate:.*$/m, '')
    response = response.gsub(/^== Running in interactive mode\. ==$.*?^$/m, '')
    response = response.gsub(/^>.*$/m, '')
    response = response.gsub(/^llama_perf.*$/m, '')
    response = response.gsub(/^llama_memory.*$/m, '')
    response = response.gsub(/^ggml_metal.*$/m, '')
    response = response.gsub(/^\*\*\*.*$/m, '')
    response = response.gsub(/^EOF by user$/m, '')
    response = response.gsub(/\[end of text\]/i, '')  # Remove [end of text] markers
    response = response.gsub(/```json\s*/, '')        # Remove opening ```json
    response = response.gsub(/```\s*$/, '')           # Remove closing ```
    response = response.strip

    # Try to find JSON in the response
    json_match = response.match(/\{.*?\}/m)
    if json_match
      json_match[0].strip
    else
      response
    end
  end

  def print_summary(total_time)
    avg_runtime = @total_processed > 0 ? @total_runtime_ms.to_f / @total_processed : 0
    median_runtime = calculate_median_runtime

    log(:info, "=== INFERENCE SUMMARY ===")
    log(:info, "Total processing time: #{total_time.round(2)} seconds")
    log(:info, "Successfully processed: #{@total_processed}")
    log(:info, "Skipped records: #{@skipped_records}")
    log(:info, "Failed records: #{@total_failed}")
    log(:info, "Average runtime per sample: #{avg_runtime.round(2)} ms")
    log(:info, "Median runtime per sample: #{median_runtime.round(2)} ms")
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

  def calculate_median_runtime
    return 0 if @individual_runtimes.empty?

    sorted_runtimes = @individual_runtimes.sort
    length = sorted_runtimes.length

    if length.odd?
      sorted_runtimes[length / 2]
    else
      (sorted_runtimes[length / 2 - 1] + sorted_runtimes[length / 2]) / 2.0
    end
  end

  def setup_grammar
    if @use_grammar
      @grammar_file ||= setup_default_grammar
      unless @grammar_file && File.exist?(@grammar_file)
        log(:warn, "Grammar file not available, proceeding without grammar enforcement")
        @use_grammar = false
      end
    end

    # Log grammar status after setup
    if @use_grammar && @grammar_file && File.exist?(@grammar_file)
      log(:info, "JSON grammar enforcement: ENABLED (#{@grammar_file})")
    elsif @use_grammar
      log(:warn, "JSON grammar enforcement: REQUESTED but grammar file not available")
    else
      log(:info, "JSON grammar enforcement: DISABLED")
    end
  end

  def setup_default_grammar
    schema_dir = File.join(__dir__, '..', 'schema')
    grammar_dir = File.join(__dir__, '..', 'grammar')

    FileUtils.mkdir_p(schema_dir) unless Dir.exist?(schema_dir)
    FileUtils.mkdir_p(grammar_dir) unless Dir.exist?(grammar_dir)

    schema_file = File.join(schema_dir, 'biosample_schema.json')
    grammar_file = File.join(grammar_dir, 'biosample.gbnf')

    # Create schema if it doesn't exist
    unless File.exist?(schema_file)
      create_default_schema(schema_file)
    end

    # Generate grammar if it doesn't exist or schema is newer
    if !File.exist?(grammar_file) || File.mtime(schema_file) > File.mtime(grammar_file)
      if generate_grammar_from_schema(schema_file, grammar_file)
        log(:info, "Generated grammar file: #{grammar_file}")
      else
        log(:warn, "Failed to generate grammar file")
        return nil
      end
    else
      log(:debug, "Using existing grammar file: #{grammar_file}")
    end

    grammar_file
  end

  def create_default_schema(schema_file)
    schema = {
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "title" => "BioSample Classification Schema",
      "type" => "object",
      "required" => ["disease", "treatments", "gene-modification"],
      "additionalProperties" => false,
      "properties" => {
        "disease" => { "type" => "boolean" },
        "treatments" => { "type" => "boolean" },
        "gene-modification" => { "type" => "boolean" }
      }
    }

    File.write(schema_file, JSON.pretty_generate(schema))
    log(:info, "Created default schema: #{schema_file}")
  end

  def generate_grammar_from_schema(schema_file, grammar_file)
    # Try to load the grammar generator
    generator_path = File.join(__dir__, 'generate_grammar.rb')

    if File.exist?(generator_path)
      begin
        require_relative 'generate_grammar'
        return GrammarGenerator.generate_from_schema(schema_file, grammar_file, @llama_cpp_path)
      rescue => e
        log(:warn, "Failed to use external grammar generator: #{e.message}")
      end
    end

    # Fallback: create simple built-in grammar
    grammar = <<~GBNF
      root ::= object
      object ::= "{" ws "\"disease\"" ws ":" ws boolean ws "," ws "\"treatments\"" ws ":" ws boolean ws "," ws "\"gene-modification\"" ws ":" ws boolean ws "}"
      boolean ::= "true" | "false"
      ws ::= [ \\t\\n\\r]*
    GBNF

    File.write(grammar_file, grammar)
    log(:info, "Created built-in grammar file: #{grammar_file}")
    true
  rescue => e
    log(:error, "Grammar generation failed: #{e.message}")
    false
  end

  def detect_llama_cpp_path
    paths = [
      ENV['LLAMA_CPP_PATH'],
      "~/repos/llama.cpp",
      "/usr/local/llama.cpp",
      "/opt/llama.cpp"
    ].compact.map { |path| File.expand_path(path) }

    paths.find { |path| File.exist?(path) } || "~/repos/llama.cpp"
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

    opts.on("--no-grammar", "Disable JSON grammar enforcement (default: enabled)") do
      options[:use_grammar] = false
    end

    opts.on("--grammar-file PATH", "Custom GBNF grammar file path (default: auto-generated)") do |path|
      options[:grammar_file] = path
    end

    opts.on("--llama-cpp-path PATH", "Path to llama.cpp directory for grammar generation") do |path|
      options[:llama_cpp_path] = path
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
