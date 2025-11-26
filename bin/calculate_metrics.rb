#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'optparse'

# Performance Metrics Calculator for BioSample Classification
# Calculates accuracy, recall, precision, and specificity for disease, treatment, and gene classification tasks
class MetricsCalculator
  def initialize(gold_standard_file, predictions_file)
    @gold_standard_file = gold_standard_file
    @predictions_file = predictions_file
    @gold_standard = {}
    @predictions = {}
    @categories = []
  end

  def run
    load_gold_standard
    load_predictions
    calculate_and_display_metrics
  end

  private

  def load_gold_standard
    puts "Loading gold standard from: #{@gold_standard_file}"

    CSV.foreach(@gold_standard_file, headers: true, col_sep: "\t") do |row|
      id = row['id']
      @gold_standard[id] = {
        'disease' => normalize_boolean(row['disease']),
        'treatment' => normalize_boolean(row['treatment']),
        'gene' => normalize_boolean(row['gene'])
      }
    end

    puts "Loaded #{@gold_standard.size} gold standard records"
    @categories = ['disease', 'treatment', 'gene']
  end

  def load_predictions
    puts "Loading predictions from: #{@predictions_file}"

    CSV.foreach(@predictions_file, headers: true, col_sep: "\t") do |row|
      id = row['id']
      @predictions[id] = {
        'disease' => normalize_boolean(row['disease']),
        'treatment' => normalize_boolean(row['treatments'] || row['treatment']), # Handle both column names
        'gene' => normalize_boolean(row['gene-modification'] || row['gene']) # Handle both column names
      }
    end

    puts "Loaded #{@predictions.size} prediction records"
  end

  def normalize_boolean(value)
    case value.to_s.downcase.strip
    when 'true', 't', '1', 'yes'
      true
    when 'false', 'f', '0', 'no'
      false
    else
      false # Default to false for any unclear values
    end
  end

  def calculate_and_display_metrics
    puts "\n" + "="*80
    puts "BIOSAMPLE CLASSIFICATION PERFORMANCE METRICS"
    puts "="*80

    # Find common IDs between gold standard and predictions
    common_ids = @gold_standard.keys & @predictions.keys
    missing_in_predictions = @gold_standard.keys - @predictions.keys
    missing_in_gold_standard = @predictions.keys - @gold_standard.keys

    puts "\nData Coverage:"
    puts "  Gold standard records: #{@gold_standard.size}"
    puts "  Prediction records: #{@predictions.size}"
    puts "  Common records for evaluation: #{common_ids.size}"
    puts "  Missing in predictions: #{missing_in_predictions.size}"
    puts "  Missing in gold standard: #{missing_in_gold_standard.size}"

    if missing_in_predictions.size > 0
      puts "\nSample IDs missing in predictions:"
      missing_in_predictions.first(10).each { |id| puts "  #{id}" }
      puts "  ... (#{missing_in_predictions.size - 10} more)" if missing_in_predictions.size > 10
    end

    if missing_in_gold_standard.size > 0
      puts "\nSample IDs missing in gold standard:"
      missing_in_gold_standard.first(10).each { |id| puts "  #{id}" }
      puts "  ... (#{missing_in_gold_standard.size - 10} more)" if missing_in_gold_standard.size > 10
    end

    # Calculate metrics for each category
    @categories.each do |category|
      puts "\n" + "-"*60
      puts "CATEGORY: #{category.upcase}"
      puts "-"*60

      metrics = calculate_metrics_for_category(common_ids, category)
      display_confusion_matrix(metrics)
      display_performance_metrics(metrics)
    end

    # Overall summary
    puts "\n" + "="*80
    puts "OVERALL SUMMARY"
    puts "="*80

    overall_metrics = calculate_overall_metrics(common_ids)
    display_overall_summary(overall_metrics)
  end

  def calculate_metrics_for_category(common_ids, category)
    tp = tn = fp = fn = 0

    common_ids.each do |id|
      gold = @gold_standard[id][category]
      pred = @predictions[id][category]

      if gold && pred
        tp += 1  # True Positive
      elsif !gold && !pred
        tn += 1  # True Negative
      elsif !gold && pred
        fp += 1  # False Positive
      elsif gold && !pred
        fn += 1  # False Negative
      end
    end

    {
      tp: tp, tn: tn, fp: fp, fn: fn,
      total: common_ids.size
    }
  end

  def calculate_overall_metrics(common_ids)
    overall_tp = overall_tn = overall_fp = overall_fn = 0

    @categories.each do |category|
      metrics = calculate_metrics_for_category(common_ids, category)
      overall_tp += metrics[:tp]
      overall_tn += metrics[:tn]
      overall_fp += metrics[:fp]
      overall_fn += metrics[:fn]
    end

    {
      tp: overall_tp,
      tn: overall_tn,
      fp: overall_fp,
      fn: overall_fn,
      total: common_ids.size * @categories.size
    }
  end

  def display_confusion_matrix(metrics)
    puts "\nConfusion Matrix:"
    puts "                  Predicted"
    puts "                 True  False"
    puts "  Actual  True   #{sprintf('%4d', metrics[:tp])}  #{sprintf('%4d', metrics[:fn])}"
    puts "         False   #{sprintf('%4d', metrics[:fp])}  #{sprintf('%4d', metrics[:tn])}"
  end

  def display_performance_metrics(metrics)
    tp, tn, fp, fn = metrics[:tp], metrics[:tn], metrics[:fp], metrics[:fn]

    # Calculate metrics with safety checks for division by zero
    accuracy = safe_divide(tp + tn, tp + tn + fp + fn)
    recall = safe_divide(tp, tp + fn)  # Sensitivity / True Positive Rate
    precision = safe_divide(tp, tp + fp)  # Positive Predictive Value
    specificity = safe_divide(tn, tn + fp)  # True Negative Rate
    f1_score = safe_divide(2 * precision * recall, precision + recall)

    puts "\nPerformance Metrics:"
    puts "  Accuracy:    #{sprintf('%.4f', accuracy)} (#{sprintf('%.2f%%', accuracy * 100)})"
    puts "  Recall:      #{sprintf('%.4f', recall)} (#{sprintf('%.2f%%', recall * 100)}) - TP/(TP+FN)"
    puts "  Precision:   #{sprintf('%.4f', precision)} (#{sprintf('%.2f%%', precision * 100)}) - TP/(TP+FP)"
    puts "  Specificity: #{sprintf('%.4f', specificity)} (#{sprintf('%.2f%%', specificity * 100)}) - TN/(TN+FP)"
    puts "  F1-Score:    #{sprintf('%.4f', f1_score)} (#{sprintf('%.2f%%', f1_score * 100)})"

    puts "\nRaw Counts:"
    puts "  True Positives:  #{tp}"
    puts "  True Negatives:  #{tn}"
    puts "  False Positives: #{fp}"
    puts "  False Negatives: #{fn}"
    puts "  Total:           #{tp + tn + fp + fn}"
  end

  def display_overall_summary(metrics)
    tp, tn, fp, fn = metrics[:tp], metrics[:tn], metrics[:fp], metrics[:fn]

    accuracy = safe_divide(tp + tn, tp + tn + fp + fn)
    recall = safe_divide(tp, tp + fn)
    precision = safe_divide(tp, tp + fp)
    specificity = safe_divide(tn, tn + fp)
    f1_score = safe_divide(2 * precision * recall, precision + recall)

    puts "Micro-averaged metrics across all categories:"
    puts "  Overall Accuracy:    #{sprintf('%.4f', accuracy)} (#{sprintf('%.2f%%', accuracy * 100)})"
    puts "  Overall Recall:      #{sprintf('%.4f', recall)} (#{sprintf('%.2f%%', recall * 100)})"
    puts "  Overall Precision:   #{sprintf('%.4f', precision)} (#{sprintf('%.2f%%', precision * 100)})"
    puts "  Overall Specificity: #{sprintf('%.4f', specificity)} (#{sprintf('%.2f%%', specificity * 100)})"
    puts "  Overall F1-Score:    #{sprintf('%.4f', f1_score)} (#{sprintf('%.2f%%', f1_score * 100)})"

    puts "\nTotal Counts Across All Categories:"
    puts "  True Positives:  #{tp}"
    puts "  True Negatives:  #{tn}"
    puts "  False Positives: #{fp}"
    puts "  False Negatives: #{fn}"
    puts "  Total:           #{tp + tn + fp + fn}"
  end

  def safe_divide(numerator, denominator)
    return 0.0 if denominator == 0
    numerator.to_f / denominator.to_f
  end
end

# Command line interface
def main
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-g", "--gold-standard FILE", "Gold standard TSV file") do |file|
      options[:gold_standard] = file
    end

    opts.on("-p", "--predictions FILE", "Predictions TSV file") do |file|
      options[:predictions] = file
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  # Default file paths if not specified
  options[:gold_standard] ||= "./tests/gold-standard/human-curator-results.tsv"
  options[:predictions] ||= "./output/20251127_041619/normalized_predictions.tsv"

  # Validate files exist
  unless File.exist?(options[:gold_standard])
    puts "Error: Gold standard file not found: #{options[:gold_standard]}"
    exit 1
  end

  unless File.exist?(options[:predictions])
    puts "Error: Predictions file not found: #{options[:predictions]}"
    exit 1
  end

  # Run the metrics calculation
  calculator = MetricsCalculator.new(options[:gold_standard], options[:predictions])
  calculator.run
end

# Run the script if called directly
if __FILE__ == $0
  main
end
