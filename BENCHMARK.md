# BioSample Classification Benchmark

This document tracks performance benchmarks for the BioSample classification pipeline across different sample sizes and configurations.

## Benchmark Methodology

### Test Environment
- **Hardware**: [Record CPU, RAM, GPU if applicable]
- **Model**: [Specify LLM model used]
- **Context Size**: [e.g., 4096 tokens]
- **Batch Size**: [e.g., 8]
- **Concurrency**: [For vLLM tests]

### Metrics Tracked
- **Total Processing Time**: Wall-clock time for entire batch
- **Throughput**: Samples per second
- **Average Runtime**: Mean time per sample (ms)
- **Median Runtime**: Median time per sample (ms)
- **Success Rate**: Percentage of successful predictions
- **Memory Usage**: Peak RAM consumption

## Local LLM Benchmarks (llama.cpp)

| Sample Count | Total Time | Throughput (samples/sec) | Avg Runtime (ms) | Median Runtime (ms) | Success Rate | Memory Peak |
|--------------|------------|-------------------------|------------------|-------------------|--------------|-------------|
| 10           | -          | -                       | -                | -                 | -            | -           |
| 100          | -          | -                       | -                | -                 | -            | -           |
| 1000         | -          | -                       | -                | -                 | -            | -           |

### Model Configuration
```
Model: [Model path/name]
Context Size: 4096
Batch Size: 8
Temperature: 0
Top-p: 0.9
Max Tokens: 64
```

## vLLM API Benchmarks

| Sample Count | Total Time | Throughput (samples/sec) | Avg Runtime (ms) | Median Runtime (ms) | Success Rate | Concurrency | Memory Peak |
|--------------|------------|-------------------------|------------------|-------------------|--------------|-------------|-------------|
| 10           | -          | -                       | -                | -                 | -            | 4           | -           |
| 100          | -          | -                       | -                | -                 | -            | 4           | -           |
| 1000         | -          | -                       | -                | -                 | -            | 4           | -           |

### API Configuration
```
Model: [Model name]
Endpoint: [API endpoint]
Concurrency: 4
Temperature: 0
Top-p: 0.9
Max Tokens: 64
```

## Pipeline Benchmarks (End-to-End)

Complete pipeline timing from raw JSON to QA sample output.

| Sample Count | Extraction | Validation | Inference | Normalization | QA Sample | Total Time | Throughput |
|--------------|------------|------------|-----------|---------------|-----------|------------|------------|
| 10           | -          | -          | -         | -             | -         | -          | -          |
| 100          | -          | -          | -         | -             | -         | -          | -          |
| 1000         | -          | -          | -         | -             | -         | -          | -          |

## Runtime Distribution Analysis

### 10 Sample Test
```
Min Runtime: - ms
Max Runtime: - ms
P50 (Median): - ms
P95: - ms
P99: - ms
Standard Deviation: - ms
```

### 100 Sample Test
```
Min Runtime: - ms
Max Runtime: - ms
P50 (Median): - ms
P95: - ms
P99: - ms
Standard Deviation: - ms
```

### 1000 Sample Test
```
Min Runtime: - ms
Max Runtime: - ms
P50 (Median): - ms
P95: - ms
P99: - ms
Standard Deviation: - ms
```

## Performance Optimization Notes

### Bottlenecks Identified
- [ ] LLM inference speed
- [ ] JSON parsing overhead
- [ ] File I/O operations
- [ ] Network latency (vLLM)
- [ ] Memory allocation

### Optimization Strategies Tested
- [ ] Batch size tuning
- [ ] Concurrency level adjustment
- [ ] Context window optimization
- [ ] Model quantization effects
- [ ] Prompt length reduction

## Comparative Analysis

### Local vs API Performance
| Metric | Local LLM | vLLM API | Difference |
|--------|-----------|----------|------------|
| Throughput (1000 samples) | - | - | - |
| Average Latency | - | - | - |
| Resource Usage | - | - | - |

### Scalability Observations
- **10 → 100 samples**: [Performance scaling notes]
- **100 → 1000 samples**: [Performance scaling notes]
- **Memory scaling**: [Memory usage patterns]
- **Throughput scaling**: [Linear/sublinear scaling analysis]

## Hardware Requirements

### Minimum Requirements (10-100 samples)
- CPU: -
- RAM: -
- Storage: -
- GPU (if applicable): -

### Recommended Requirements (1000+ samples)
- CPU: -
- RAM: -
- Storage: -
- GPU (if applicable): -

## Running Benchmarks

### Quick Benchmark (10 samples)
```bash
# Create test data
head -n 10 large_dataset.json > test_10.json

# Run benchmark
time bash bin/run_all_local.sh test_10.json --model model.gguf
```

### Full Benchmark Suite
```bash
# Run all benchmark sizes
./scripts/run_benchmarks.sh
```

### Performance Monitoring
```bash
# Monitor resource usage during benchmark
htop &
bash bin/run_all_local.sh dataset.json --model model.gguf

# Extract timing metrics from logs
grep -E "runtime_ms|Average runtime|Median runtime" *.log
```

## Benchmark History

### Version 1.0 (Initial Implementation)
- Date: [YYYY-MM-DD]
- Commit: [Git commit hash]
- Notes: [Performance characteristics]

### Version 1.1 (Logging Improvements)
- Date: [YYYY-MM-DD] 
- Commit: [Git commit hash]
- Notes: [Performance impact of logging changes]

---

**Last Updated**: [Date]
**Benchmark Runner**: [Name/System]
**Next Benchmark Due**: [Date]