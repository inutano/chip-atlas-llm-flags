#!/usr/bin/env ruby

# Mock vLLM server for testing purposes
# Simulates the vLLM REST API endpoints

require 'webrick'
require 'json'

class MockVLLMServer
  def initialize(port = 8000)
    @port = port
    @server = WEBrick::HTTPServer.new(Port: @port, Logger: WEBrick::Log.new("/dev/null"))
    setup_routes
  end

  def start
    puts "Starting mock vLLM server on port #{@port}"
    puts "Health endpoint: http://localhost:#{@port}/health"
    puts "Completions endpoint: http://localhost:#{@port}/v1/completions"
    puts "Press Ctrl+C to stop"

    trap 'INT' do
      @server.shutdown
    end

    @server.start
  end

  private

  def setup_routes
    # Health check endpoint
    @server.mount_proc '/health' do |req, res|
      res.status = 200
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate({status: 'healthy'})
    end

    # Completions endpoint
    @server.mount_proc '/v1/completions' do |req, res|
      handle_completions(req, res)
    end
  end

  def handle_completions(req, res)
    begin
      # Parse request
      unless req.request_method == 'POST'
        res.status = 405
        res.body = 'Method not allowed'
        return
      end

      payload = JSON.parse(req.body)
      prompt = payload['prompt'] || ''

      # Debug output
      puts "DEBUG: Received prompt:"
      puts prompt[0...200] + (prompt.length > 200 ? "..." : "")
      puts "DEBUG: ---"

      # Generate mock response based on prompt content
      prediction = generate_mock_prediction(prompt)

      # Format as vLLM API response
      api_response = {
        'id' => "mock_#{rand(100000)}",
        'object' => 'text_completion',
        'created' => Time.now.to_i,
        'model' => payload['model'] || 'mock-model',
        'choices' => [
          {
            'text' => prediction,
            'index' => 0,
            'logprobs' => nil,
            'finish_reason' => 'stop'
          }
        ],
        'usage' => {
          'prompt_tokens' => prompt.length / 4,
          'completion_tokens' => prediction.length / 4,
          'total_tokens' => (prompt.length + prediction.length) / 4
        }
      }

      res.status = 200
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(api_response)

    rescue JSON::ParserError => e
      res.status = 400
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate({error: "Invalid JSON: #{e.message}"})
    rescue => e
      res.status = 500
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate({error: "Server error: #{e.message}"})
    end
  end

  def generate_mock_prediction(prompt)
    # Analyze prompt content and generate appropriate mock responses
    disease = false
    treatments = false
    gene_modification = false

    # Check for disease indicators - be more specific
    if prompt.match?(/breast cancer|tumor|adenocarcinoma|leukemia|diabetes|patient.*disease/i)
      disease = true
    end

    # Check for treatment indicators
    if prompt.match?(/treated with|doxorubicin|metformin|therapy.*drug|treatment.*hours/i)
      treatments = true
    end

    # Check for gene modification indicators
    if prompt.match?(/CRISPR|knockout|overexpression|transgenic|gene.modified|method.*CRISPR/i)
      gene_modification = true
    end

    # Special case: healthy donor should be all false
    if prompt.match?(/healthy donor|normal.*fibroblast/i) && !prompt.match?(/disease|treatment|CRISPR/i)
      disease = false
      treatments = false
      gene_modification = false
    end

    # Return JSON prediction
    JSON.generate({
      'disease' => disease,
      'treatments' => treatments,
      'gene-modification' => gene_modification
    })

    puts "DEBUG: Generated prediction: disease=#{disease}, treatments=#{treatments}, gene_modification=#{gene_modification}"
  end
end

# Start the server if run directly
if __FILE__ == $0
  port = ARGV[0] ? ARGV[0].to_i : 8000
  server = MockVLLMServer.new(port)
  server.start
end
