#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'

# Generate realistic sample predictions for testing the metrics calculator
# This creates a predictions file with varied performance to demonstrate different metric scenarios

def load_gold_standard(file_path)
  data = {}
  CSV.foreach(file_path, headers: true, col_sep: "\t") do |row|
    id = row['id']
    data[id] = {
      'disease' => row['disease'] == 'T',
      'treatment' => row['treatment'] == 'T',
      'gene' => row['gene'] == 'T'
    }
  end
  data
end

def generate_predictions(gold_standard, disease_accuracy: 0.8, treatment_accuracy: 0.75, gene_accuracy: 0.85)
  predictions = {}

  gold_standard.each do |id, gold|
    predictions[id] = {
      'disease' => predict_with_accuracy(gold['disease'], disease_accuracy),
      'treatment' => predict_with_accuracy(gold['treatment'], treatment_accuracy),
      'gene' => predict_with_accuracy(gold['gene'], gene_accuracy)
    }
  end

  predictions
end

def predict_with_accuracy(true_value, accuracy)
  # Generate prediction based on accuracy rate
  # For true values: correct with given accuracy
  # For false values: correct with given accuracy

  if rand < accuracy
    true_value  # Correct prediction
  else
    !true_value # Incorrect prediction
  end
end

def write_predictions(predictions, output_file)
  CSV.open(output_file, 'w', col_sep: "\t") do |csv|
    # Write header
    csv << ['id', 'disease', 'treatments', 'gene-modification']

    # Write predictions
    predictions.each do |id, pred|
      csv << [
        id,
        pred['disease'].to_s.downcase,
        pred['treatment'].to_s.downcase,
        pred['gene'].to_s.downcase
      ]
    end
  end
end

def main
  # File paths
  gold_standard_file = './tests/gold-standard/human-curator-results.tsv'
  output_file = './output/20251127_041619/normalized_predictions.tsv'

  # Check if gold standard exists
  unless File.exist?(gold_standard_file)
    puts "Error: Gold standard file not found: #{gold_standard_file}"
    exit 1
  end

  # Set random seed for reproducible results
  srand(42)

  # Load gold standard
  puts "Loading gold standard from: #{gold_standard_file}"
  gold_standard = load_gold_standard(gold_standard_file)
  puts "Loaded #{gold_standard.size} records"

  # Generate predictions with different accuracy levels for each category
  puts "Generating realistic predictions..."
  puts "  Disease accuracy: 85%"
  puts "  Treatment accuracy: 78%"
  puts "  Gene accuracy: 82%"

  predictions = generate_predictions(
    gold_standard,
    disease_accuracy: 0.85,
    treatment_accuracy: 0.78,
    gene_accuracy: 0.82
  )

  # Write predictions to file
  puts "Writing predictions to: #{output_file}"
  write_predictions(predictions, output_file)

  puts "Sample predictions generated successfully!"

  # Show some statistics
  disease_trues = predictions.values.count { |p| p['disease'] }
  treatment_trues = predictions.values.count { |p| p['treatment'] }
  gene_trues = predictions.values.count { |p| p['gene'] }

  puts "\nPrediction Statistics:"
  puts "  Disease positives: #{disease_trues}/#{predictions.size} (#{(disease_trues * 100.0 / predictions.size).round(1)}%)"
  puts "  Treatment positives: #{treatment_trues}/#{predictions.size} (#{(treatment_trues * 100.0 / predictions.size).round(1)}%)"
  puts "  Gene positives: #{gene_trues}/#{predictions.size} (#{(gene_trues * 100.0 / predictions.size).round(1)}%)"
end

if __FILE__ == $0
  main
end
