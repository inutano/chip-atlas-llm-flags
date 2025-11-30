#!/usr/bin/env ruby

require 'csv'
require 'optparse'

class ComparisonTableGenerator
  def initialize(human_file, prediction_file, output_file)
    @human_file = human_file
    @prediction_file = prediction_file
    @output_file = output_file
    @human_data = {}
    @prediction_data = {}
  end

  def generate
    load_human_data
    load_prediction_data
    generate_comparison_table
    puts "Comparison table generated: #{@output_file}"
  end

  private

  def load_human_data
    CSV.foreach(@human_file, headers: true, col_sep: "\t") do |row|
      id = row['id']
      @human_data[id] = {
        disease: row['disease'] == 'T',
        treatment: row['treatment'] == 'T',
        gene: row['gene'] == 'T'
      }
    end
    puts "Loaded #{@human_data.size} human curated records"
  end

  def load_prediction_data
    CSV.foreach(@prediction_file, headers: true, col_sep: "\t") do |row|
      id = row['id']
      @prediction_data[id] = {
        disease: row['disease'] == 'true',
        treatments: row['treatments'] == 'true',
        gene_modification: row['gene-modification'] == 'true'
      }
    end
    puts "Loaded #{@prediction_data.size} prediction records"
  end

  def generate_comparison_table
    CSV.open(@output_file, 'w', col_sep: "\t") do |csv|
      # Write header
      csv << [
        'id', 'link', 'URL',
        'pred_disease', 'pred_treatments', 'pred_gene-modification',
        'human_disease', 'human_treatment', 'human_gene-modification',
        'comp_disease', 'comp_treatments', 'comp_gene-modification'
      ]

      # Get all IDs that appear in both datasets
      common_ids = (@human_data.keys & @prediction_data.keys).sort

      common_ids.each do |id|
        human = @human_data[id]
        pred = @prediction_data[id]

        # Convert boolean to F/T format for output
        pred_disease = pred[:disease] ? 'T' : 'F'
        pred_treatments = pred[:treatments] ? 'T' : 'F'
        pred_gene_mod = pred[:gene_modification] ? 'T' : 'F'

        human_disease = human[:disease] ? 'T' : 'F'
        human_treatment = human[:treatment] ? 'T' : 'F'
        human_gene = human[:gene] ? 'T' : 'F'

        # Calculate comparison results
        comp_disease = calculate_comparison(pred[:disease], human[:disease])
        comp_treatments = calculate_comparison(pred[:treatments], human[:treatment])
        comp_gene_mod = calculate_comparison(pred[:gene_modification], human[:gene])

        # Generate URL
        url = "https://www.ncbi.nlm.nih.gov/biosample/?term=#{id}"

        csv << [
          id, 'Link', url,
          pred_disease, pred_treatments, pred_gene_mod,
          human_disease, human_treatment, human_gene,
          comp_disease, comp_treatments, comp_gene_mod
        ]
      end
    end

    puts "Generated comparison for #{(@human_data.keys & @prediction_data.keys).size} common records"
  end

  def calculate_comparison(predicted, actual)
    if predicted && actual
      'TP'  # True Positive
    elsif !predicted && !actual
      'TN'  # True Negative
    elsif predicted && !actual
      'FP'  # False Positive
    else
      'FN'  # False Negative
    end
  end
end

# Command line interface
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-h", "--human FILE", "Human curated reference file") do |file|
    options[:human] = file
  end

  opts.on("-p", "--prediction FILE", "Prediction file") do |file|
    options[:prediction] = file
  end

  opts.on("-o", "--output FILE", "Output comparison table file") do |file|
    options[:output] = file
  end

  opts.on("--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate required arguments
unless options[:human] && options[:prediction] && options[:output]
  puts "Error: All options (--human, --prediction, --output) are required"
  puts "Use --help for usage information"
  exit 1
end

# Validate input files exist
unless File.exist?(options[:human])
  puts "Error: Human reference file not found: #{options[:human]}"
  exit 1
end

unless File.exist?(options[:prediction])
  puts "Error: Prediction file not found: #{options[:prediction]}"
  exit 1
end

# Generate comparison table
generator = ComparisonTableGenerator.new(
  options[:human],
  options[:prediction],
  options[:output]
)

generator.generate
