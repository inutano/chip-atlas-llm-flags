# BioSample Classification Performance Metrics

This document describes the performance evaluation tools for the BioSample classification pipeline, which assesses the accuracy of LLM-based predictions for disease status, treatment applications, and gene modifications.

## Overview

The metrics calculation system provides comprehensive performance evaluation by comparing LLM predictions against human-curated gold standard annotations. It calculates standard classification metrics for three categories:

- **Disease Classification**: Whether a sample is disease-related
- **Treatment Classification**: Whether a sample involves treatments/interventions  
- **Gene Modification Classification**: Whether a sample involves genetic modifications

## Quick Start

### Using the Wrapper Script (Recommended)

```bash
# Basic evaluation with default files
./bin/evaluate_performance.sh

# Verbose output
./bin/evaluate_performance.sh -v

# Save results to file
./bin/evaluate_performance.sh -o ./results/metrics_$(date +%Y%m%d_%H%M%S).txt

# Custom files
./bin/evaluate_performance.sh -g ./my-gold-standard.tsv -p ./my-predictions.tsv
```

### Using the Core Script Directly

```bash
# Default files
ruby bin/calculate_metrics.rb

# Custom files
ruby bin/calculate_metrics.rb -g tests/gold-standard/human-curator-results.tsv -p output/20251127_041619/normalized_predictions.tsv
```

## File Formats

### Gold Standard Format (`human-curator-results.tsv`)

Tab-separated values with the following structure:

```tsv
id	disease	treatment	gene
SAMN06273137	F	T	F
SAMN06616141	F	F	F
SAMN06687719	T	F	T
...
```

- `id`: BioSample accession (SAMN/SAME/SAMD format)
- `disease`: `T` (disease-related) or `F` (not disease-related)
- `treatment`: `T` (treatment-related) or `F` (not treatment-related)  
- `gene`: `T` (gene modification) or `F` (no gene modification)

### Predictions Format (`normalized_predictions.tsv`)

Tab-separated values with the following structure:

```tsv
id	disease	treatments	gene-modification
SAMN06273137	false	true	false
SAMN06616141	false	false	false
SAMN06687719	true	false	true
...
```

- `id`: BioSample accession (must match gold standard)
- `disease`: `true`/`false` (boolean strings)
- `treatments`: `true`/`false` (note: plural form)
- `gene-modification`: `true`/`false` (note: hyphenated form)

**Note**: The system automatically handles column name variations and boolean format differences.

## Metrics Calculated

### Per-Category Metrics

For each category (disease, treatment, gene modification):

| Metric | Formula | Description |
|--------|---------|-------------|
| **Accuracy** | (TP+TN)/(TP+TN+FP+FN) | Overall correctness |
| **Recall (Sensitivity)** | TP/(TP+FN) | True positive rate |
| **Precision** | TP/(TP+FP) | Positive predictive value |
| **Specificity** | TN/(TN+FP) | True negative rate |
| **F1-Score** | 2×(Precision×Recall)/(Precision+Recall) | Harmonic mean of precision and recall |

Where:
- **TP**: True Positives (correctly identified positives)
- **TN**: True Negatives (correctly identified negatives)  
- **FP**: False Positives (incorrectly identified as positive)
- **FN**: False Negatives (missed positives)

### Overall Metrics

Micro-averaged metrics across all three categories, providing system-wide performance assessment.

## Sample Output

```
================================================================================
BIOSAMPLE CLASSIFICATION PERFORMANCE METRICS
================================================================================

Data Coverage:
  Gold standard records: 283
  Prediction records: 283
  Common records for evaluation: 283
  Missing in predictions: 0
  Missing in gold standard: 0

------------------------------------------------------------
CATEGORY: DISEASE
------------------------------------------------------------

Confusion Matrix:
                  Predicted
                 True  False
  Actual  True     26     4
         False     44   209

Performance Metrics:
  Accuracy:    0.8304 (83.04%)
  Recall:      0.8667 (86.67%) - TP/(TP+FN)
  Precision:   0.3714 (37.14%) - TP/(TP+FP)
  Specificity: 0.8261 (82.61%) - TN/(TN+FP)
  F1-Score:    0.5200 (52.00%)

Raw Counts:
  True Positives:  26
  True Negatives:  209
  False Positives: 44
  False Negatives: 4
  Total:           283

[Similar output for TREATMENT and GENE categories]

================================================================================
OVERALL SUMMARY
================================================================================
Micro-averaged metrics across all categories:
  Overall Accuracy:    0.8127 (81.27%)
  Overall Recall:      0.8395 (83.95%)
  Overall Precision:   0.5056 (50.56%)
  Overall Specificity: 0.8064 (80.64%)
  Overall F1-Score:    0.6311 (63.11%)
```

## Understanding the Results

### Interpreting Confusion Matrix

```
                  Predicted
                 True  False
  Actual  True   [TP]  [FN]
         False   [FP]  [TN]
```

- **High TP, Low FN**: Good at detecting positive cases (high recall)
- **High TN, Low FP**: Good at identifying negative cases (high specificity)
- **High TP, Low FP**: Predictions are reliable when positive (high precision)

### Metric Interpretation

- **High Accuracy**: Overall system performance is good
- **High Recall**: System catches most positive cases (few missed positives)
- **High Precision**: When system predicts positive, it's usually correct
- **High Specificity**: System correctly identifies negative cases
- **High F1-Score**: Good balance between precision and recall

### Common Patterns

| Pattern | Interpretation | Possible Causes |
|---------|----------------|-----------------|
| High Specificity, Low Recall | Conservative model | Model threshold too high, insufficient training data for positives |
| High Recall, Low Precision | Liberal model | Model threshold too low, high false positive rate |
| Low overall metrics | Poor model performance | Model needs retraining, data quality issues |
| Imbalanced performance across categories | Category-specific issues | Different data quality or model bias per category |

## Troubleshooting

### File Format Issues

```bash
# Check file structure
head -n 5 tests/gold-standard/human-curator-results.tsv
head -n 5 output/20251127_041619/normalized_predictions.tsv

# Check for encoding issues
file tests/gold-standard/human-curator-results.tsv
```

### Missing Records

The system reports missing records in either file. Common causes:
- Pipeline failures for specific samples
- Data filtering at different stages
- ID format inconsistencies

### Data Quality Issues

```bash
# Check for duplicate IDs
cut -f1 tests/gold-standard/human-curator-results.tsv | sort | uniq -d

# Validate ID formats
grep -E '^SAM[NDE][A-Z]?\d+' tests/gold-standard/human-curator-results.tsv | wc -l
```

## Scripts and Tools

### Core Scripts

- `bin/calculate_metrics.rb`: Core metrics calculation engine
- `bin/evaluate_performance.sh`: User-friendly wrapper script
- `bin/generate_sample_predictions.rb`: Generate realistic test predictions

### Usage Examples

```bash
# Generate sample predictions for testing
ruby bin/generate_sample_predictions.rb

# Run evaluation with custom accuracy levels
# (Modify generate_sample_predictions.rb for different scenarios)

# Batch evaluation of multiple prediction files
for pred_file in output/*/normalized_predictions.tsv; do
    echo "Evaluating: $pred_file"
    ./bin/evaluate_performance.sh -p "$pred_file" -o "results/metrics_$(basename $(dirname $pred_file)).txt"
done
```

## Integration with Pipeline

The metrics calculation integrates with the main BioSample classification pipeline:

1. **Pipeline generates**: `output/[timestamp]/normalized_predictions.tsv`
2. **Gold standard**: `tests/gold-standard/human-curator-results.tsv`
3. **Evaluation**: `./bin/evaluate_performance.sh`
4. **Results**: Performance metrics for pipeline validation

## Development and Testing

### Adding New Metrics

To add custom metrics, modify `calculate_metrics.rb`:

```ruby
def calculate_custom_metric(metrics)
  # Add your custom calculation here
  # metrics hash contains: tp, tn, fp, fn, total
end
```

### Testing with Different Data

```ruby
# Generate predictions with specific accuracy patterns
predictions = generate_predictions(
  gold_standard,
  disease_accuracy: 0.90,    # High accuracy for disease
  treatment_accuracy: 0.60,  # Lower accuracy for treatment  
  gene_accuracy: 0.80       # Medium accuracy for gene
)
```

## References

- [Confusion Matrix](https://en.wikipedia.org/wiki/Confusion_matrix)
- [Classification Metrics](https://scikit-learn.org/stable/modules/model_evaluation.html#classification-metrics)
- [BioSample Database](https://www.ncbi.nlm.nih.gov/biosample/)

## Contributing

When adding new evaluation metrics:

1. Update `calculate_metrics.rb` with the new calculation
2. Add tests in `bin/generate_sample_predictions.rb` 
3. Update this documentation
4. Test with various data scenarios