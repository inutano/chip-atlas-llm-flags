#!/bin/bash

# run_all_local.sh - Complete local pipeline orchestration
#
# USAGE:
#   bash bin/run_all_local.sh INPUT_JSON --model MODEL_PATH [--ctx CTX] [--batch BATCH]
#
# DESCRIPTION:
#   Orchestrates the complete BioSample classification pipeline using local LLM.
#   Dynamically handles timestamped filenames and provides timing information.
#   All output is logged to both stdout and a centralized log file in the output directory.
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

# Global variables for logging
LOG_FILE=""
PIPELINE_START_TIME=""

# Function to setup logging
setup_logging() {
    local output_dir=$1
    LOG_FILE="$output_dir/pipeline.log"
    PIPELINE_START_TIME=$(date +%s)

    # Create log file and add header
    {
        echo "========================================="
        echo "BioSample Classification Pipeline Log"
        echo "========================================="
        echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Output directory: $output_dir"
        echo "Command: $0 $*"
        echo ""
    } > "$LOG_FILE"

    echo "Log file created: $LOG_FILE"
}

# Function to log messages to both stdout and log file
log_message() {
    local message="$*"
    echo "$message"
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

# Function to execute command with logging
execute_with_logging() {
    local command="$*"
    log_message "Executing: $command"

    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        # Execute command and capture both stdout and stderr, tee to both console and log
        eval "$command" 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
        if [[ $exit_code -ne 0 ]]; then
            log_message "ERROR: Command failed with exit code $exit_code"
            exit $exit_code
        fi
    else
        # Fallback if logging not setup
        eval "$command"
    fi
}

# Function to print step headers with timing
print_step() {
    local step_num=$1
    local step_name=$2

    log_message ""
    log_message "========================================="
    log_message "STEP $step_num: $step_name"
    log_message "========================================="
    log_message "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Function to print step completion with elapsed time
print_completion() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    log_message "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "Elapsed time: ${elapsed} seconds"
    log_message ""
}

# Function to find the most recent output directory
find_latest_output_dir() {
    local latest_dir=$(ls -td output/*/ 2>/dev/null | head -n1)
    if [[ -z "$latest_dir" ]]; then
        log_message "ERROR: No output directories found"
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
        log_message "ERROR: File not found: $filepath"
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

# Initial pipeline information (before logging setup)
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

execute_with_logging "ruby bin/extract_biosample.rb \"$INPUT_JSON\""
latest_output_dir=$(find_latest_output_dir)

# Setup logging now that we have the output directory
setup_logging "$latest_output_dir"

latest_extracted=$(find_file_in_output_dir "$latest_output_dir" "biosample_extracted.jsonl")
log_message "Latest extracted file: $latest_extracted"
log_message "Output directory: $latest_output_dir"

print_completion $step_start

# STEP 2: Validate extracted data
step_start=$(date +%s)
print_step "2" "Validate Extracted Data"

execute_with_logging "ruby bin/validate_extracted.rb \"$latest_extracted\""

print_completion $step_start

# STEP 3: Run local LLM inference
step_start=$(date +%s)
print_step "3" "Run Local LLM Inference"

execute_with_logging "ruby bin/run_llama_local.rb \"$latest_extracted\" $LLM_ARGS"
latest_predictions=$(find_file_in_output_dir "$latest_output_dir" "biosample_predictions.jsonl")
log_message "Latest predictions file: $latest_predictions"

print_completion $step_start

# STEP 4: Normalize predictions
step_start=$(date +%s)
print_step "4" "Normalize Predictions"

execute_with_logging "ruby bin/normalize_predictions.rb \"$latest_predictions\""
latest_normalized=$(find_file_in_output_dir "$latest_output_dir" "normalized_predictions.jsonl")
log_message "Latest normalized file: $latest_normalized"

print_completion $step_start

# STEP 5: Create QA sample
step_start=$(date +%s)
print_step "5" "Create QA Sample"

execute_with_logging "ruby bin/make_qa_sample.rb \"$latest_extracted\" \"$latest_normalized\" --n 200"
latest_qa_sample=$(find_file_in_output_dir "$latest_output_dir" "qa_sample.tsv")
log_message "Latest QA sample file: $latest_qa_sample"

print_completion $step_start

# Final summary
pipeline_end_time=$(date +%s)
total_elapsed=$((pipeline_end_time - PIPELINE_START_TIME))

log_message "========================================="
log_message "PIPELINE COMPLETED SUCCESSFULLY"
log_message "========================================="
log_message "Input file: $INPUT_JSON"
log_message "Output directory: $latest_output_dir"
log_message "Log file: $LOG_FILE"
log_message "Final outputs:"
log_message "  - Extracted: $latest_extracted"
log_message "  - Predictions: $latest_predictions"
log_message "  - Normalized: $latest_normalized"
log_message "  - QA Sample: $latest_qa_sample"
log_message ""
log_message "All output files are organized in: $latest_output_dir"
log_message "Total pipeline runtime: ${total_elapsed} seconds"
log_message "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
log_message "========================================="
