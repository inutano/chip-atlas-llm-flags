# ChIP-Atlas LLM Flags

This repository extracts structured metadata from BioSample JSON files and classifies them into disease, treatments, and gene-modification flags using large language models. The system enables systematic analysis of ChIP-seq datasets and their associated biological contexts through automated classification of experimental conditions.

## Dependencies

### Core Requirements
- **Ruby** (≥ 2.7)
  - Standard libraries: `json`, `optparse`, `logger`, `time`, `fileutils`, `csv`
- **Local LLM Inference**:
  - [llama.cpp](https://github.com/ggerganov/llama.cpp) with compatible GGUF model files
  - OR vLLM server with REST API endpoint
- **System Tools**: `curl` or `wget` for downloading test data

### Optional Tools
- **bash** for pipeline orchestration scripts
- **Python 3** or **Ruby** for JSON validation during testing

### Hardware Requirements
- **Minimum** (10-100 samples): 4GB RAM, 2 CPU cores
- **Recommended** (1000+ samples): 16GB RAM, 8+ CPU cores
- **GPU**: Optional but recommended for large-scale inference

## Pipeline Overview

The BioSample classification pipeline consists of five main steps:

```
Raw BioSample JSON → Extract → Validate → Inference → Normalize → QA Sample
     (Step 3)        (Step 4)   (Step 5)    (Step 6)     (Step 7)
```

### Step 3: Data Extraction (`bin/extract_biosample.rb`)
- **JSON Format**: Extracts BioSample records with valid accessions (SAMN*, SAMD*, SAMEA*)
- **TSV Format**: Processes experimentList.tab files (Column 1=ID, Column 9=Title, Column 10=Key=value attributes)
- Auto-detects input format based on file extension and content
- Combines title, description, organism, and attributes into unified structure
- **Output**: `biosample_extracted_YYYYMMDD_HHMMSS.jsonl`

### Step 4: Data Validation (`bin/validate_extracted.rb`)
- Validates JSON format and required fields
- Ensures BioSample IDs start with "SAM"
- Fixes missing title/description/organism fields
- **Output**: Validation report with pass/fail status

### Step 5: LLM Inference
#### Local Inference (`bin/run_llama_local.rb`)
- Uses llama.cpp with GGUF model files
- Deterministic inference (temperature = 0)
- **Output**: `biosample_predictions_YYYYMMDD_HHMMSS.jsonl`

#### API Inference (`bin/run_vllm.rb`)
- Uses vLLM REST API endpoints
- Concurrent processing for improved throughput
- **Output**: `biosample_predictions_YYYYMMDD_HHMMSS.jsonl`

### Step 6: Normalization (`bin/normalize_predictions.rb`)
- Extracts compact boolean predictions
- Deduplicates records (keeps most recent)
- Filters out error flags
- **Output**: `normalized_predictions_YYYYMMDD_HHMMSS.jsonl`

### Step 7: QA Sample Generation (`bin/make_qa_sample.rb`)
- Joins extracted data with predictions
- Extracts attribute keywords for manual review
- Optional random sampling (--n flag)
- **Output**: `qa_sample_YYYYMMDD_HHMMSS.tsv`

## Classification Schema

The system classifies BioSample metadata into three boolean flags based on **explicit mentions only**:

- **`disease`**: Pathological conditions, cancer, tumors, patient-derived samples
- **`treatments`**: Chemical treatments, drugs, therapeutic interventions
- **`gene-modification`**: CRISPR, knockout, overexpression, transgenic modifications

Detailed classification rules are documented in [SPEC.md](SPEC.md).

The LLM prompt template and inference parameters are specified in [PROMPT.md](PROMPT.md).

## Example Run

### Quick Start with Pipeline Script
```bash
# Download example data and run complete pipeline
bash tests/run_minimal.sh

# Or run with your own data
bash bin/run_all_local.sh input.json --model model.gguf
```

### Manual Step-by-Step Execution
```bash
# Step 1: Extract BioSample data (JSON or TSV format)
ruby bin/extract_biosample.rb biosamples.json --outdir output/
ruby bin/extract_biosample.rb experimentList.tab --outdir output/

# Step 2: Validate extracted data
ruby bin/validate_extracted.rb output/biosample_extracted_*.jsonl

# Step 3: Run LLM inference (local)
ruby bin/run_llama_local.rb output/biosample_extracted_*.jsonl \
  --model /path/to/model.gguf --ctx 4096 --batch 8

# Step 3: Run LLM inference (API alternative)
ruby bin/run_vllm.rb output/biosample_extracted_*.jsonl \
  --model Qwen/Qwen2.5-32B-Instruct \
  --endpoint http://localhost:8000 --concurrency 4

# Step 4: Normalize predictions
ruby bin/normalize_predictions.rb output/biosample_predictions_*.jsonl

# Step 5: Create QA sample
ruby bin/make_qa_sample.rb output/biosample_extracted_*.jsonl \
  output/normalized_predictions_*.jsonl --n 200
```

## Input/Output Examples

### Input Examples

**JSON Format** (biosamples.json):
```json
[
  {
    "accession": "SAMN12345678",
    "title": "MCF-7 breast cancer cells treated with doxorubicin",
    "description": "MCF-7 breast adenocarcinoma cells treated with 1µM doxorubicin for 48 hours to study drug resistance",
    "organism": "Homo sapiens",
    "taxid": "9606",
    "attributes": {
      "cell_line": "MCF-7",
      "disease": "adenocarcinoma",
      "treatment": "doxorubicin",
      "concentration": "1 µM"
    }
  }
]
```

**TSV Format** (experimentList.tab):
```
EXP001	sample1	ChIP-seq	Homo sapiens	9606	2023-01-15	PRJNA123456	SRX123456	MCF-7 breast cancer cells	cell_line=MCF-7;disease=adenocarcinoma;treatment=doxorubicin;concentration=1µM
```
Column mapping: 1=Experiment ID, 9=Title, 10=Key=value pairs (semicolon separated)

### Output Examples
Both input formats produce the same output structure:

**Normalized Predictions** (`normalized_predictions_*.jsonl`):
```json
{"id":"SAMN12345678","disease":true,"treatments":true,"gene-modification":false}
{"id":"EXP001","disease":true,"treatments":true,"gene-modification":false}
```

**QA Sample** (`qa_sample_*.tsv`):
| id | title | description | organism | attr_disease_like | attr_treatments_like | attr_gene_mod_like | disease | treatments | gene-modification |
|---|---|---|---|---|---|---|---|---|---|
| SAMN12345678 | MCF-7 breast cancer cells treated with doxorubicin | MCF-7 breast adenocarcinoma cells treated with 1µM doxorubicin for 48 hours... | Homo sapiens (TaxID: 9606) | disease: adenocarcinoma | treatment: doxorubicin; concentration: 1 µM | | true | true | false |

## Output Files

All output files include timestamps (`YYYYMMDD_HHMMSS`) for version tracking:

### Primary Outputs
- **`biosample_extracted_*.jsonl`**: Cleaned and structured BioSample records
- **`biosample_predictions_*.jsonl`**: Raw LLM predictions with metadata
- **`normalized_predictions_*.jsonl`**: Final boolean classifications
- **`qa_sample_*.tsv`**: Human-readable quality assessment data

### Log Files
- **`biosample_extracted_*.log`**: Extraction processing logs
- **`biosample_predictions_*.log`**: LLM inference logs with timing
- **`normalized_predictions_*.log`**: Normalization processing logs
- **`qa_sample_*.log`**: QA sample generation logs

### Log Monitoring
Extract processing statistics with:
```bash
grep -E "Successfully processed|Skipped records|Failed records" *.log
```

## Performance & Benchmarking

### Inference Configuration
- **Deterministic inference**: `temperature = 0` for reproducible results
- **Context window**: 4096 tokens (configurable)
- **Max tokens**: 64 tokens for JSON response
- **Retry policy**: Up to 3 attempts with fallback to default values

### Throughput Expectations
- **Local inference**: ~1-5 samples/second (model dependent)
- **vLLM API**: ~10-50 samples/second (server dependent)
- **Complete pipeline**: ~1000 samples in 5-10 minutes

See [BENCHMARK.md](BENCHMARK.md) for detailed performance metrics and optimization guidance.

## Troubleshooting

### Common Issues

**"No valid BioSample accession found" (JSON) / "Invalid experiment ID" (TSV)**
- **JSON**: Ensure records have `accession` field with format SAMN*, SAMD*, or SAMEA*
- **TSV**: Verify Column 1 contains valid experiment IDs (non-empty, reasonable length)
- Check that ID fields are not empty or malformed

**"LLM binary not found or not working"**
- Verify llama.cpp installation and model path
- Test binary with: `./llama-cli --help`
- Ensure model file exists and is readable

**"Transport error" in vLLM runs**
- Check vLLM server is running: `curl http://localhost:8000/health`
- Verify model name matches server configuration
- Check network connectivity and firewall settings

**"Invalid JSON in API response"**
- LLM output may be malformed; check temperature settings
- Try reducing prompt complexity or model load
- Monitor retry counts in logs

**High memory usage**
- Reduce batch size with `--batch` parameter
- Lower context window with `--ctx` parameter
- Process smaller file chunks

### Debugging Commands

```bash
# Test extraction on small sample
head -n 10 large_input.json > test_small.json
ruby bin/extract_biosample.rb test_small.json

# Test TSV format
head -n 5 experimentList.tab > test_small.tab
ruby bin/extract_biosample.rb test_small.tab

# Validate specific file
ruby bin/validate_extracted.rb extracted_file.jsonl

# Check LLM binary
./llama-cli --help

# Monitor resource usage
htop & ruby bin/run_llama_local.rb input.jsonl --model model.gguf

# Parse timing statistics
grep "Average runtime\|Median runtime" *.log
```

### Environment Issues
- **Ruby version**: Ensure Ruby ≥ 2.7 with `ruby --version`
- **JSON parsing**: Large files may require increased memory limits
- **File permissions**: Ensure write access to output directories
- **Path issues**: Use absolute paths for model files and binaries

### Getting Help
1. Check log files for detailed error messages
2. Run minimal test: `bash tests/run_minimal.sh`
3. Verify dependencies and system requirements
4. Review [SPEC.md](SPEC.md) for classification rules
5. Check [BENCHMARK.md](BENCHMARK.md) for performance expectations

## Project Structure

```
chip-atlas-llm-flags/
├── bin/                    # Executable scripts
│   ├── extract_biosample.rb
│   ├── validate_extracted.rb
│   ├── run_llama_local.rb
│   ├── run_vllm.rb
│   ├── normalize_predictions.rb
│   ├── make_qa_sample.rb
│   └── run_all_local.sh    # Pipeline orchestration
├── tests/
│   ├── run_minimal.sh      # End-to-end test
│   └── fixtures/           # Test data
├── SPEC.md                 # Classification schema
├── PROMPT.md               # LLM prompt template
├── BENCHMARK.md            # Performance metrics
└── README.md               # This file
```

---

**Version**: v0.1.0  
**License**: MIT  
**Last Updated**: 2025-11-12