#!/bin/bash

# run_all_local.sh - Complete local pipeline orchestration
#
# USAGE:
#   bash bin/run_all_local.sh INPUT_JSON --model MODEL_PATH [--ctx CTX] [--batch BATCH]
#
# DESCRIPTION:
#   Orchestrates the complete BioSample classification pipeline using local LLM.
#   Dynamically handles timestamped filenames and provides timing information.
#
# STEPS:
#   1. Extract BioSample data
#   2. Validate extracted data
#   3. Run local LLM inference
#   4. Normalize predictions
#   5. Create QA sample
#
# EXAMPLES:
#   bash bin/run_all_local.sh data.json --model model.gguf
#   bash bin/run_all_local.sh input.json --model model.gguf --ctx 8192 --batch 16
#

set -euo pipefail

# Function to print step headers with timing
print_step() {
    local step_num=$1
    local step_name=$2
    echo ""
    echo "========================================="
    echo "STEP $step_num: $step_name"
    echo "========================================="
    echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Function to print step completion with elapsed time
print_completion() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Elapsed time: ${elapsed} seconds"
    echo ""
}

# Function to find the most recent output directory
find_latest_output_dir() {
    local latest_dir=$(ls -td output/*/ 2>/dev/null | head -n1)
    if [[ -z "$latest_dir" ]]; then
        echo "ERROR: No output directories found" >&2
        exit 1
    fi
    echo "${latest_dir%/}"  # Remove trailing slash
}

# Function to find file in output directory
find_file_in_output_dir() {
    local output_dir=$1
    local filename=$2
    local filepath="$output_dir/$filename"
    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        exit 1
    fi
    echo "$filepath"
}

# Parse command line arguments
if [[ $# -lt 3 ]]; then
    echo "Usage: bash bin/run_all_local.sh INPUT_JSON --model MODEL_PATH [--ctx CTX] [--batch BATCH]"
    echo ""
    echo "Required:"
    echo "  INPUT_JSON    Path to BioSample JSON file"
    echo "  --model       Path to GGUF model file"
    echo ""
    echo "Optional:"
    echo "  --ctx         Context window size (default: 4096)"
    echo "  --batch       Batch size (default: 8)"
    exit 1
fi

INPUT_JSON=$1
shift

# Forward all remaining arguments to the LLM script
LLM_ARGS="$@"

# Validate input file
if [[ ! -f "$INPUT_JSON" ]]; then
    echo "ERROR: Input file not found: $INPUT_JSON"
    exit 1
fi

echo "========================================="
echo "BioSample Classification Pipeline"
echo "========================================="
echo "Input file: $INPUT_JSON"
echo "LLM arguments: $LLM_ARGS"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# STEP 1: Extract BioSample data
step_start=$(date +%s)
print_step "1" "Extract BioSample Data"

ruby bin/extract_biosample.rb "$INPUT_JSON"
latest_output_dir=$(find_latest_output_dir)
latest_extracted=$(find_file_in_output_dir "$latest_output_dir" "biosample_extracted.jsonl")
echo "Latest extracted file: $latest_extracted"
echo "Output directory: $latest_output_dir"

print_completion $step_start

# STEP 2: Validate extracted data
step_start=$(date +%s)
print_step "2" "Validate Extracted Data"

ruby bin/validate_extracted.rb "$latest_extracted"

print_completion $step_start

# STEP 3: Run local LLM inference
step_start=$(date +%s)
print_step "3" "Run Local LLM Inference"

ruby bin/run_llama_local.rb "$latest_extracted" $LLM_ARGS
latest_predictions=$(find_file_in_output_dir "$latest_output_dir" "biosample_predictions.jsonl")
echo "Latest predictions file: $latest_predictions"

print_completion $step_start

# STEP 4: Normalize predictions
step_start=$(date +%s)
print_step "4" "Normalize Predictions"

ruby bin/normalize_predictions.rb "$latest_predictions"
latest_normalized=$(find_file_in_output_dir "$latest_output_dir" "normalized_predictions.jsonl")
echo "Latest normalized file: $latest_normalized"

print_completion $step_start

# STEP 5: Create QA sample
step_start=$(date +%s)
print_step "5" "Create QA Sample"

ruby bin/make_qa_sample.rb "$latest_extracted" "$latest_normalized" --n 200
latest_qa_sample=$(find_file_in_output_dir "$latest_output_dir" "qa_sample.tsv")
echo "Latest QA sample file: $latest_qa_sample"

print_completion $step_start

# Final summary
echo "========================================="
echo "PIPELINE COMPLETED SUCCESSFULLY"
echo "========================================="
echo "Input file: $INPUT_JSON"
echo "Output directory: $latest_output_dir"
echo "Final outputs:"
echo "  - Extracted: $latest_extracted"
echo "  - Predictions: $latest_predictions"
echo "  - Normalized: $latest_normalized"
echo "  - QA Sample: $latest_qa_sample"
echo ""
echo "All output files are organized in: $latest_output_dir"
echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
