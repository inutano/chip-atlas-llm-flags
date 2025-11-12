# Classification Schema and Decision Rules

## Overview

This document defines the classification schema and decision rules for extracting structured metadata from BioSample JSON files. The system classifies biological samples into three categories: disease, treatments, and gene-modification flags.

## Output Format

The output must be a JSON object with exactly three boolean fields:

```json
{
  "disease": bool,
  "treatments": bool, 
  "gene-modification": bool
}
```

## General Principles

- **Explicit mentions only**: Classification is based solely on explicit textual mentions in the sample metadata. No inference or guessing is allowed.
- **English text only**: All analyzed text is in English and raw wording must be preserved in analysis.
- **Boolean values only**: Each flag must be either `true` or `false`, no null or undefined values.

## Classification Rules

### Disease Flag (`disease`)

Set to `true` if the sample description contains explicit mentions of:

- **Disease names**: cancer, diabetes, Alzheimer's, Parkinson's, etc.
- **Pathological conditions**: tumor, inflammation, infection, autoimmune disorders
- **Disease-related terminology**: malignant, benign, metastasis, carcinoma, sarcoma
- **Medical conditions**: hypertension, obesity, metabolic syndrome
- **Genetic disorders**: cystic fibrosis, sickle cell disease, muscular dystrophy
- **Infectious diseases**: COVID-19, influenza, tuberculosis, HIV

**Examples of qualifying text**:
- "breast cancer cell line"
- "diabetic patients"
- "tumor tissue sample"
- "infected with virus"

Set to `false` if:
- No explicit disease terminology is present
- Only healthy/normal samples are described
- General biological processes without pathological context

### Treatments Flag (`treatments`)

Set to `true` if the sample description contains explicit mentions of:

- **Drug names**: specific pharmaceutical compounds (aspirin, metformin, etc.)
- **Treatment modalities**: chemotherapy, radiation therapy, immunotherapy
- **Therapeutic interventions**: surgery, transplantation, gene therapy
- **Drug classes**: antibiotics, antiviral, anti-inflammatory, chemotherapeutic agents
- **Treatment protocols**: dosage regimens, treatment duration, combination therapies
- **Experimental compounds**: novel drugs, investigational treatments

**Examples of qualifying text**:
- "treated with doxorubicin"
- "post-chemotherapy samples"
- "drug-resistant cells"
- "following antibiotic treatment"

Set to `false` if:
- No treatment-related terminology is present
- Only control/untreated samples are described
- Standard laboratory procedures without therapeutic intent

### Gene-Modification Flag (`gene-modification`)

Set to `true` if the sample description contains explicit mentions of:

- **Genetic engineering techniques**: CRISPR, gene knockout, gene editing
- **Transgenic modifications**: transgenic animals, genetically modified organisms
- **Gene manipulation**: overexpression, knockdown, knock-in, knockout
- **Recombinant technologies**: recombinant proteins, viral vectors, plasmid transfection
- **Specific modified genes**: mutant strains, gene deletions, insertions
- **Genetic constructs**: reporter genes, fusion proteins, tagged proteins

**Examples of qualifying text**:
- "CRISPR-edited cells"
- "knockout mice"
- "transgenic model"
- "overexpressing GFP"
- "gene-modified organisms"

Set to `false` if:
- No genetic modification terminology is present
- Only wild-type or naturally occurring samples
- Standard breeding without genetic engineering

## Decision Priority

When multiple flags could apply to a single sample:
- Each flag is evaluated independently
- A sample can have multiple `true` flags simultaneously
- All three flags can be `true` for a single sample if conditions are met

## Quality Control

- Preserve original text casing and spelling in analysis
- Document specific phrases that triggered each classification
- Maintain traceability between input text and classification decisions
- Flag ambiguous cases for manual review when necessary