# Quick Usage Guide

This directory contains tools for converting BioSample metadata from a redundant nested structure to a simplified key=value format.

## Files Overview

- `input.jsonl` - Original BioSample metadata (193 records)
- `convert_biosample_attributes.rb` - Main conversion script
- `output_converted.jsonl` - Converted metadata with simplified structure
- `compare_structures.rb` - Analysis tool to compare original vs converted
- `demo_improvements.rb` - Interactive demo of improvements
- `README.md` - Detailed documentation

## Quick Start

### 1. Convert BioSample Data
```bash
ruby convert_biosample_attributes.rb input.jsonl output.jsonl
```

### 2. Analyze Sample Structure
```bash
ruby convert_biosample_attributes.rb --analyze input.jsonl --samples 5
```

### 3. Compare Results
```bash
ruby compare_structures.rb input.jsonl output_converted.jsonl
```

### 4. See Interactive Demo
```bash
ruby demo_improvements.rb input.jsonl output_converted.jsonl
```

## Key Benefits

- **82% file size reduction** (467KB → 82KB)
- **Simplified access**: `record['attributes']['cell_type']` vs complex nested traversal
- **Standardized keys**: Consistent attribute naming across records
- **Better performance**: Direct hash access instead of array searching

## Structure Transformation

**Before:**
```json
{
  "Attributes": {
    "Attribute": [
      {
        "attribute_name": "cell type",
        "harmonized_name": "cell_type",
        "display_name": "cell type",
        "content": "GMP"
      }
    ]
  }
}
```

**After:**
```json
{
  "attributes": {
    "cell_type": "GMP"
  }
}
```

## Common Use Cases

### Find records by attribute
```ruby
cancer_samples = records.select { |r| 
  r['attributes']['cell_type']&.include?('cancer') 
}
```

### Count unique values
```ruby
cell_types = records.map { |r| r['attributes']['cell_type'] }.compact.uniq
```

### Filter by organism
```ruby
human_samples = records.select { |r| 
  r['organism']['taxonomy_name'] == 'Homo sapiens' 
}
```

## Script Options

All scripts support `--help` for detailed usage information:
```bash
ruby convert_biosample_attributes.rb --help
```
