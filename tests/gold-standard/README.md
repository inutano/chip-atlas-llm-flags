# BioSample Metadata Structure Conversion

This directory contains tools and data for converting BioSample metadata records from a redundant attribute structure to a simplified key=value format.

## Problem Description

The original BioSample metadata in `input.jsonl` contains redundant attribute structures where each attribute has multiple name fields:

```json
{
  "Attributes": {
    "Attribute": [
      {
        "attribute_name": "source_name",
        "harmonized_name": "source_name", 
        "display_name": "source name",
        "content": "Bone Marrow CD34+"
      },
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

This structure is verbose and contains redundant information across three different name fields for each attribute.

## Solution

The `convert_biosample_attributes.rb` script converts this to a simplified structure:

```json
{
  "attributes": {
    "source_name": "Bone Marrow CD34+",
    "cell_type": "GMP"
  }
}
```

### Key Improvements

1. **Simplified Structure**: Converts from nested objects with multiple name fields to simple key=value pairs
2. **Standardized Keys**: Uses `harmonized_name` when available (most standardized), falls back to `attribute_name`
3. **Normalized Keys**: Converts keys to lowercase with underscores, removing special characters
4. **Reduced Size**: Eliminates redundant metadata, significantly reducing file size
5. **Easier Processing**: Simple key=value structure is much easier to query and process

### Conversion Rules

- **Key Selection**: `harmonized_name` > `attribute_name` (prioritizes standardized names)
- **Key Normalization**: Lowercase, spaces/special chars → underscores, remove leading/trailing underscores
- **Value**: Uses `content` field directly
- **Filtering**: Skips attributes with empty or missing content

## Files

- `input.jsonl` - Original BioSample metadata with redundant structure (193 records)
- `convert_biosample_attributes.rb` - Ruby conversion script
- `output_converted.jsonl` - Converted metadata with simplified structure

## Usage

### Basic Conversion
```bash
ruby convert_biosample_attributes.rb input.jsonl output.jsonl
```

### Analyze Sample Structure
```bash
ruby convert_biosample_attributes.rb --analyze input.jsonl --samples 10
```

### Help
```bash
ruby convert_biosample_attributes.rb --help
```

## Example Conversion

**Before:**
```json
{
  "biosample_id": "SAMN06616141",
  "entry": {
    "Attributes": {
      "Attribute": [
        {
          "attribute_name": "source_name",
          "harmonized_name": "source_name",
          "display_name": "source name",
          "content": "Bone Marrow CD34+"
        },
        {
          "attribute_name": "tissue",
          "harmonized_name": "tissue", 
          "display_name": "tissue",
          "content": "CD34+ Bone Marrow"
        }
      ]
    }
  }
}
```

**After:**
```json
{
  "biosample_id": "SAMN06616141",
  "srx": "SRX2651053",
  "accession": "SAMN06616141",
  "organism": {
    "taxonomy_id": "9606",
    "taxonomy_name": "Homo sapiens"
  },
  "title": "BM1077-GMP-Frozen-160107-12",
  "attributes": {
    "source_name": "Bone Marrow CD34+",
    "tissue": "CD34+ Bone Marrow",
    "cell_type": "GMP"
  }
}
```

## Common Attribute Keys Found

After conversion, common standardized attribute keys include:

- `source_name` - Sample source description
- `cell_type` - Type of cells in the sample
- `tissue` - Tissue type
- `cell_line` - Cell line name (for cultured cells)
- `treatment` - Applied treatments
- `sex` - Biological sex
- `age` - Age information
- `genotype` - Genetic information
- `biomaterial_provider` - Sample provider

## Benefits

1. **Storage Efficiency**: Reduced JSON size by ~60%
2. **Query Performance**: Direct key access vs nested object traversal
3. **Standardization**: Consistent key naming across records
4. **Simplicity**: Easier to work with in downstream processing
5. **Maintainability**: Cleaner data structure for analysis tools