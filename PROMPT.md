# LLM Prompt for BioSample Classification

## Inference Parameters

```yaml
temperature: 0
top_p: 0.9
max_tokens: 64
stop: none
retries: 3
```

## Prompt Template

```
You are an information extraction engine. 
Task: From the given BioSample metadata (English), decide three boolean flags using ONLY explicit statements in the text. 
Do not use external knowledge or guess. If not explicitly stated, the flag must be false.

Definitions:
- disease: true only if the text explicitly states a disease/condition, tumor, patient-derived origin, or a disease term in the sample description (e.g., "breast cancer", "AML", "tumor tissue", "leukemia cell line"). Proper names without disease words (e.g., "MCF7", "HeLa") are not enough.
- treatments: true only if any intervention on the sample is explicitly described, including chemicals/drugs or physical/environmental stimuli (e.g., treated with, exposed to, stimulated by, heat shock, UV, irradiation, hypoxia, starvation). Routine culture conditions (e.g., DMEM + 10% FBS) or fixation/staining/preservation steps are not counted.
- gene-modification: true only if gene engineering is explicitly described (KO, KD, CRISPR, overexpression, transgenic, CRISPRa/i, shRNA, stable line expressing X, GFP/FLAG-tagged, etc.). Germline/background variants or cell line's known mutations are not counted unless the engineering operation itself is stated.

Output format:
Return EXACTLY one compact JSON object with these three keys and boolean values:
{"disease": true/false, "treatments": true/false, "gene-modification": true/false}

Now analyze this BioSample (pre-extracted fields, original wording preserved; English only):

<title> {TITLE_OR_NAME} 
<description> {DESCRIPTION} 
<organism> {ORGANISM_OR_TAXID} 
<attributes>
{KEY1}: {VAL1}
{KEY2}: {VAL2}
...
```

## Usage Notes

- Replace `{TITLE_OR_NAME}`, `{DESCRIPTION}`, `{ORGANISM_OR_TAXID}` with actual extracted values
- Replace `{KEY1}: {VAL1}`, `{KEY2}: {VAL2}`, etc. with actual attribute key-value pairs
- Preserve original wording from source BioSample metadata
- Ensure all text is in English before processing
- Expected response is a single JSON object with exactly three boolean fields
```

Now I need to commit this file: