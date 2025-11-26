#!/bin/bash

# Performance Evaluation Wrapper Script
# Easy-to-use script for calculating BioSample classification performance metrics

set -e

# Default paths
GOLD_STANDARD="./tests/gold-standard/human-curator-results.tsv"
PREDICTIONS="./output/20251127_041619/normalized_predictions.tsv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_SCRIPT="$SCRIPT_DIR/calculate_metrics.rb"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Performance evaluation script for BioSample classification pipeline.

OPTIONS:
    -g, --gold-standard FILE    Path to gold standard TSV file
                               (default: $GOLD_STANDARD)

    -p, --predictions FILE      Path to predictions TSV file
                               (default: $PREDICTIONS)

    -o, --output FILE          Save metrics to output file (optional)

    -v, --verbose              Enable verbose output

    -h, --help                 Show this help message

EXAMPLES:
    # Use default files
    $0

    # Specify custom files
    $0 -g ./my-gold-standard.tsv -p ./my-predictions.tsv

    # Save output to file
    $0 -o ./results/metrics_$(date +%Y%m%d_%H%M%S).txt

    # Verbose mode
    $0 -v

METRICS CALCULATED:
    - Accuracy: (TP+TN)/(TP+TN+FP+FN)
    - Recall (Sensitivity): TP/(TP+FN)
    - Precision: TP/(TP+FP)
    - Specificity: TN/(TN+FP)
    - F1-Score: 2*(Precision*Recall)/(Precision+Recall)

CATEGORIES EVALUATED:
    - Disease classification
    - Treatment classification
    - Gene modification classification

EOF
}

# Parse command line arguments
VERBOSE=false
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--gold-standard)
            GOLD_STANDARD="$2"
            shift 2
            ;;
        -p|--predictions)
            PREDICTIONS="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to check if file exists
check_file() {
    if [[ ! -f "$1" ]]; then
        print_error "File not found: $1"
        exit 1
    fi
}

# Function to check if Ruby script exists
check_script() {
    if [[ ! -f "$METRICS_SCRIPT" ]]; then
        print_error "Metrics calculation script not found: $METRICS_SCRIPT"
        print_error "Please ensure calculate_metrics.rb is in the bin/ directory"
        exit 1
    fi
}

# Main execution
main() {
    print_status "BioSample Classification Performance Evaluation"
    echo "=================================================================="

    if [[ "$VERBOSE" == true ]]; then
        print_status "Verbose mode enabled"
        print_status "Gold standard: $GOLD_STANDARD"
        print_status "Predictions: $PREDICTIONS"
        print_status "Script: $METRICS_SCRIPT"
        if [[ -n "$OUTPUT_FILE" ]]; then
            print_status "Output file: $OUTPUT_FILE"
        fi
        echo ""
    fi

    # Validate inputs
    print_status "Validating input files..."
    check_script
    check_file "$GOLD_STANDARD"
    check_file "$PREDICTIONS"

    # Create output directory if needed
    if [[ -n "$OUTPUT_FILE" ]]; then
        OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            print_status "Creating output directory: $OUTPUT_DIR"
            mkdir -p "$OUTPUT_DIR"
        fi
    fi

    print_success "All input files validated successfully"
    echo ""

    # Run metrics calculation
    print_status "Calculating performance metrics..."
    echo ""

    if [[ -n "$OUTPUT_FILE" ]]; then
        # Run and save to file
        ruby "$METRICS_SCRIPT" -g "$GOLD_STANDARD" -p "$PREDICTIONS" | tee "$OUTPUT_FILE"
        echo ""
        print_success "Metrics saved to: $OUTPUT_FILE"
    else
        # Run and display only
        ruby "$METRICS_SCRIPT" -g "$GOLD_STANDARD" -p "$PREDICTIONS"
    fi

    echo ""
    print_success "Performance evaluation completed!"

    if [[ "$VERBOSE" == true ]]; then
        echo ""
        print_status "Files processed:"
        print_status "  Gold standard: $GOLD_STANDARD ($(wc -l < "$GOLD_STANDARD") lines)"
        print_status "  Predictions: $PREDICTIONS ($(wc -l < "$PREDICTIONS") lines)"

        # Show file timestamps
        echo ""
        print_status "File timestamps:"
        print_status "  Gold standard: $(stat -c '%y' "$GOLD_STANDARD" 2>/dev/null || stat -f '%Sm' "$GOLD_STANDARD" 2>/dev/null || echo 'Unknown')"
        print_status "  Predictions: $(stat -c '%y' "$PREDICTIONS" 2>/dev/null || stat -f '%Sm' "$PREDICTIONS" 2>/dev/null || echo 'Unknown')"
    fi
}

# Execute main function
main "$@"
