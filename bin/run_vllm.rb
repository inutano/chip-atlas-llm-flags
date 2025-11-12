#!/usr/bin/env ruby

# run_vllm.rb - vLLM REST API inference for BioSample classification
#
# USAGE:
#   ruby bin/run_vllm.rb INPUT_JSONL --model MODEL_NAME --endpoint URL [OPTIONS]
#
# DESCRIPTION:
#   This script processes extracted BioSample JSONL files using a vLLM REST API
#   to classify samples into disease, treatments, and gene-modification flags
#   based on the prompt template in PROMPT.md.
#
# REQUIRED ARGUMENTS:
#   INPUT_JSONL   Path to extracted BioSample JSONL file
#   --model       Model name for vLLM API
#   --endpoint    vLLM API endpoint URL
#
# OPTIONS:
#   --concurrency Number of concurrent requests (default: 4)
#   --outdir      Output directory (default: current directory)
#
# OUTPUT:
#   Creates timestamped JSONL file with predictions and metadata
#
# EXAMPLES:
#   ruby bin/run_vllm.rb input.jsonl --model Qwen/Qwen2.5-32B-Instruct --endpoint http://localhost:8000
#   ruby bin/run_vllm.rb input.jsonl --model meta-llama/Llama-2-7b-chat-hf --endpoint http://vllm-server:8000 --concurrency 8
#

require 'json'
require 'optparse'
require 'net/http'
require 'uri'
require 'time'
require 'fileutils'
require 'thread'

class VLLMRunner
  def initialize(options)
    @input_file = options[:input_file]
    @model_name = options[:model_name]
    @endpoint = options[:endpoint]
    @concurrency = options[:concurrency] || 4
    @output_dir = options[:output_dir] || '.'

    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    @output_file = File.join(@output_dir, "biosample_predictions_#{@timestamp}.jsonl")
    @log_file = File.join(@output_dir, "biosample_predictions_#{@timestamp}.log")

    # Statistics
    @total_processed = 0
    @total_failed = 0
    @transport_errors = 0
    @total_runtime_ms = 0
    @retry_counts = Hash.new(0)

    # Thread safety
    @mutex = Mutex.new
    @output_mutex = Mutex.new

    setup_logging
    load_prompt_template
  end

  def run
    validate_inputs

    log(:info, "=== INFERENCE START ===")
    log(:info, "Starting vLLM inference on #{@input_file}")
    log(:info, "Model: #{@model_name}")
    log(:info, "Endpoint: #{@endpoint}")
    log(:info, "Output: #{@output_file}")
    log(:info, "Concurrency: #{@concurrency}")

    start_time = Time.now

    # Read all lines first
    lines = []
    File.foreach(@input_file) do |line|
      line = line.strip
      next if line.empty?
      lines << line
    end

    log(:info, "Found #{lines.length} records to process")

    # Process with thread pool
    File.open(@output_file, 'w') do |output|
      process_with_concurrency(lines, output)
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
    @mutex.synchronize do
      @logger.send(level, message)
    end
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

    # Test API endpoint
    begin
      uri = URI.parse(@endpoint)
      response = Net::HTTP.get_response(uri.host, '/health', uri.port)
    rescue => e
      log(:warn, "Could not verify API endpoint (#{e.message}), proceeding anyway...")
    end
  end

  def process_with_concurrency(lines, output)
    queue = Queue.new
    lines.each { |line| queue << line }

    # Start worker threads
    threads = []
    @concurrency.times do
      threads << Thread.new do
        while !queue.empty?
          begin
            line = queue.pop(true) # non-blocking pop
            process_line(line, output)
          rescue ThreadError
            # Queue is empty
            break
          rescue => e
            log(:error, "Thread error processing line: #{e.message}")
          end
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)
  end

  def process_line(line, output)
    begin
      record = JSON.parse(line)
      result = classify_sample(record)

      @output_mutex.synchronize do
        output.puts JSON.generate(result)
      end

      @mutex.synchronize do
        @total_processed += 1
        if (@total_processed % 10) == 0
          log(:info, "Processed #{@total_processed} samples...")
        end
      end

    rescue JSON::ParserError => e
      log(:error, "Invalid JSON in input line: #{e.message}")
      @mutex.synchronize { @total_failed += 1 }
    rescue => e
      log(:error, "Failed to process record: #{e.message}")
      @mutex.synchronize { @total_failed += 1 }
    end
  end

  def classify_sample(record)
    id = record['id']
    prompt = build_prompt(record)

    start_time = Time.now
    prediction, retries, error_flag = run_vllm_inference(prompt)
    runtime_ms = ((Time.now - start_time) * 1000).to_i

    @mutex.synchronize do
      @total_runtime_ms += runtime_ms
      @retry_counts[retries] += 1
      @transport_errors += 1 if error_flag == 'transport_error'
    end

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

  def run_vllm_inference(prompt)
    retries = 0
    max_retries = 3

    while retries <= max_retries
      begin
        response_text = call_vllm_api(prompt)

        # Validate JSON response
        parsed = JSON.parse(response_text)

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
          raise "Invalid prediction structure: #{response_text}"
        end

      rescue TransportError => e
        # Transport errors get special handling
        log(:warn, "Transport error: #{e.message}")
        default_prediction = {
          'disease' => false,
          'treatments' => false,
          'gene-modification' => false
        }
        return [default_prediction, retries, 'transport_error']
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

  class TransportError < StandardError; end

  def call_vllm_api(prompt)
    uri = URI.parse("#{@endpoint}/v1/completions")

    # Prepare request payload
    payload = {
      model: @model_name,
      prompt: prompt,
      temperature: 0,
      top_p: 0.9,
      max_tokens: 64,
      stop: nil
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(payload)

    begin
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise TransportError, "HTTP #{response.code}: #{response.message}"
      end

      # Parse API response
      api_response = JSON.parse(response.body)

      unless api_response['choices'] && api_response['choices'][0] && api_response['choices'][0]['text']
        raise TransportError, "Invalid API response format: #{response.body}"
      end

      response_text = api_response['choices'][0]['text'].strip

      # Extract JSON from response text
      json_match = response_text.match(/\{.*\}/m)
      if json_match
        json_match[0]
      else
        response_text
      end

    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      raise TransportError, "Network error: #{e.message}"
    rescue JSON::ParserError => e
      raise TransportError, "Invalid JSON in API response: #{e.message}"
    end
  end

  def print_summary(total_time)
    avg_runtime = @total_processed > 0 ? @total_runtime_ms.to_f / @total_processed : 0
    skipped_records = 0  # vLLM doesn't skip records, only fails them

    log(:info, "=== INFERENCE SUMMARY ===")
    log(:info, "Total processing time: #{total_time.round(2)} seconds")
    log(:info, "Successfully processed: #{@total_processed}")
    log(:info, "Skipped records: #{skipped_records}")
    log(:info, "Failed records: #{@total_failed}")
    log(:info, "Transport errors: #{@transport_errors}")
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
    opts.banner = "Usage: ruby bin/run_vllm.rb INPUT_JSONL --model MODEL_NAME --endpoint URL [OPTIONS]"

    opts.on("--model MODEL", "Model name for vLLM API (required)") do |model|
      options[:model_name] = model
    end

    opts.on("--endpoint URL", "vLLM API endpoint URL (required)") do |endpoint|
      options[:endpoint] = endpoint
    end

    opts.on("--concurrency N", Integer, "Number of concurrent requests (default: 4)") do |n|
      options[:concurrency] = n
    end

    opts.on("--outdir DIR", "Output directory (default: current directory)") do |dir|
      options[:output_dir] = dir
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "ERROR: INPUT_JSONL file is required"
    puts "Usage: ruby bin/run_vllm.rb INPUT_JSONL --model MODEL_NAME --endpoint URL [OPTIONS]"
    exit 1
  end

  unless options[:model_name]
    puts "ERROR: --model option is required"
    exit 1
  end

  unless options[:endpoint]
    puts "ERROR: --endpoint option is required"
    exit 1
  end

  options[:input_file] = ARGV[0]
  options
end

# Main execution
if __FILE__ == $0
  begin
    options = parse_arguments
    runner = VLLMRunner.new(options)
    runner.run
  rescue => e
    puts "FATAL ERROR: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end
