#!/bin/bash

# run_minimal.sh - Minimal End-to-End Test for BioSample Classification Pipeline
#
# This script downloads example BioSample data and runs the complete pipeline
# from Steps 3-9 to verify end-to-end functionality.

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
WORK_DIR="$TEST_DIR/minimal_test_run"
EXAMPLE_URL="https://raw.githubusercontent.com/dbcls/bsllmner-mk2/refs/heads/main/tests/test-data/cell_line_example.biosample.json"
EXAMPLE_FILE="cell_line_example.biosample.json"

# Mock model setup (for testing without real model)
MOCK_MODEL="mock_model.gguf"
MOCK_BINARY="mock_llama"

echo "========================================="
echo "Minimal End-to-End Pipeline Test"
echo "========================================="
echo "Project Root: $PROJECT_ROOT"
echo "Work Directory: $WORK_DIR"
echo "Test Data URL: $EXAMPLE_URL"
echo ""

# Clean up and create work directory
if [ -d "$WORK_DIR" ]; then
    echo "Cleaning up existing work directory..."
    rm -rf "$WORK_DIR"
fi

echo "Creating work directory: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download example data
echo "========================================="
echo "STEP 1: Download Example Data"
echo "========================================="

if command -v curl >/dev/null 2>&1; then
    echo "Downloading with curl..."
    curl -L -o "$EXAMPLE_FILE" "$EXAMPLE_URL"
elif command -v wget >/dev/null 2>&1; then
    echo "Downloading with wget..."
    wget -O "$EXAMPLE_FILE" "$EXAMPLE_URL"
else
    echo "ERROR: Neither curl nor wget found. Cannot download test data."
    exit 1
fi

if [ ! -f "$EXAMPLE_FILE" ]; then
    echo "ERROR: Failed to download example file"
    exit 1
fi

echo "Downloaded: $EXAMPLE_FILE ($(wc -l < "$EXAMPLE_FILE") lines)"

# Verify JSON format
if ! python3 -m json.tool "$EXAMPLE_FILE" >/dev/null 2>&1 && ! ruby -rjson -e "JSON.parse(File.read('$EXAMPLE_FILE'))" >/dev/null 2>&1; then
    echo "ERROR: Downloaded file is not valid JSON"
    exit 1
fi

echo "JSON validation: PASSED"

# Create mock LLM binary for testing
echo ""
echo "Setting up mock LLM binary..."

cat > "$MOCK_BINARY" << 'EOF'
#!/bin/bash

# Mock LLM binary for testing
if [[ "$*" == *"--help"* ]]; then
    echo "Mock LLM for testing"
    exit 0
fi

# Parse prompt file argument
PROMPT_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --prompt-file)
            PROMPT_FILE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$PROMPT_FILE" ]] || [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt file not found" >&2
    exit 1
fi

# Add small delay to simulate inference
sleep 0.1

# Read prompt and generate mock response
PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Simple keyword-based mock responses
if [[ "$PROMPT_CONTENT" == *"cancer"* ]] || [[ "$PROMPT_CONTENT" == *"tumor"* ]]; then
    echo '{"disease": true, "treatments": false, "gene-modification": false}'
elif [[ "$PROMPT_CONTENT" == *"treated"* ]] || [[ "$PROMPT_CONTENT" == *"drug"* ]]; then
    echo '{"disease": false, "treatments": true, "gene-modification": false}'
elif [[ "$PROMPT_CONTENT" == *"knockout"* ]] || [[ "$PROMPT_CONTENT" == *"CRISPR"* ]] || [[ "$PROMPT_CONTENT" == *"transfected"* ]]; then
    echo '{"disease": false, "treatments": false, "gene-modification": true}'
else
    echo '{"disease": false, "treatments": false, "gene-modification": false}'
fi

exit 0
EOF

chmod +x "$MOCK_BINARY"
touch "$MOCK_MODEL"

echo "Mock LLM binary created: $MOCK_BINARY"

# Run the complete pipeline
echo ""
echo "========================================="
echo "STEP 2: Run Complete Pipeline"
echo "========================================="

cd "$PROJECT_ROOT"

# Use the pipeline orchestration script
if [ ! -f "bin/run_all_local.sh" ]; then
    echo "ERROR: Pipeline script not found: bin/run_all_local.sh"
    exit 1
fi

echo "Running pipeline with:"
echo "  Input: $WORK_DIR/$EXAMPLE_FILE"
echo "  Model: $WORK_DIR/$MOCK_MODEL"
echo "  Binary: $WORK_DIR/$MOCK_BINARY"
echo ""

# Execute pipeline (Steps 3-9)
if ! bash bin/run_all_local.sh "$WORK_DIR/$EXAMPLE_FILE" \
    --model "$WORK_DIR/$MOCK_MODEL" \
    --binary "$WORK_DIR/$MOCK_BINARY"; then
    echo "ERROR: Pipeline execution failed"
    exit 1
fi

echo ""
echo "========================================="
echo "STEP 3: Verify Pipeline Output"
echo "========================================="

# Find the most recent output files
LATEST_NORMALIZED=$(ls -t normalized_predictions_*.jsonl 2>/dev/null | head -n1 || echo "")
LATEST_QA_SAMPLE=$(ls -t qa_sample_*.tsv 2>/dev/null | head -n1 || echo "")

if [ -z "$LATEST_NORMALIZED" ]; then
    echo "ERROR: No normalized predictions file found"
    exit 1
fi

if [ ! -f "$LATEST_NORMALIZED" ]; then
    echo "ERROR: Normalized predictions file not found: $LATEST_NORMALIZED"
    exit 1
fi

# Check that the file exists and has at least 1 line
LINE_COUNT=$(wc -l < "$LATEST_NORMALIZED" 2>/dev/null || echo "0")

if [ "$LINE_COUNT" -lt 1 ]; then
    echo "ERROR: Normalized predictions file is empty or has no lines"
    echo "File: $LATEST_NORMALIZED"
    echo "Line count: $LINE_COUNT"
    exit 1
fi

echo "Normalized predictions file: $LATEST_NORMALIZED"
echo "Line count: $LINE_COUNT"
echo "Content validation: PASSED"

# Verify JSON format of normalized output
echo ""
echo "Verifying normalized output format..."

if ! head -n1 "$LATEST_NORMALIZED" | python3 -m json.tool >/dev/null 2>&1 && \
   ! head -n1 "$LATEST_NORMALIZED" | ruby -rjson -e "JSON.parse(STDIN.read)" >/dev/null 2>&1; then
    echo "ERROR: Normalized output is not valid JSON"
    exit 1
fi

# Check for required fields in first line
FIRST_LINE=$(head -n1 "$LATEST_NORMALIZED")
if ! echo "$FIRST_LINE" | grep -q '"id"' || \
   ! echo "$FIRST_LINE" | grep -q '"disease"' || \
   ! echo "$FIRST_LINE" | grep -q '"treatments"' || \
   ! echo "$FIRST_LINE" | grep -q '"gene-modification"'; then
    echo "ERROR: Missing required fields in normalized output"
    echo "First line: $FIRST_LINE"
    exit 1
fi

echo "JSON format validation: PASSED"
echo "Required fields validation: PASSED"

# Verify QA sample output if it exists
if [ -n "$LATEST_QA_SAMPLE" ] && [ -f "$LATEST_QA_SAMPLE" ]; then
    QA_LINE_COUNT=$(wc -l < "$LATEST_QA_SAMPLE" 2>/dev/null || echo "0")
    echo ""
    echo "QA sample file: $LATEST_QA_SAMPLE"
    echo "QA sample line count: $QA_LINE_COUNT"

    if [ "$QA_LINE_COUNT" -ge 2 ]; then  # Header + at least 1 data line
        echo "QA sample validation: PASSED"
    else
        echo "WARNING: QA sample file has insufficient lines"
    fi
fi

# Final summary
echo ""
echo "========================================="
echo "TEST SUMMARY"
echo "========================================="
echo "✅ Example data downloaded successfully"
echo "✅ Pipeline executed without errors"
echo "✅ Normalized output file exists: $LATEST_NORMALIZED"
echo "✅ Output file has $LINE_COUNT lines (≥ 1 required)"
echo "✅ JSON format validation passed"
echo "✅ Required fields validation passed"

if [ -n "$LATEST_QA_SAMPLE" ] && [ -f "$LATEST_QA_SAMPLE" ]; then
    echo "✅ QA sample file created: $LATEST_QA_SAMPLE"
fi

echo ""
echo "🎉 MINIMAL END-TO-END TEST PASSED! 🎉"
echo ""
echo "Output files location: $(pwd)"
echo "Work directory: $WORK_DIR"

# Cleanup option (commented out to allow inspection)
# echo ""
# echo "Cleaning up work directory..."
# rm -rf "$WORK_DIR"

exit 0
