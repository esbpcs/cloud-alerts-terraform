#!/usr/bin/env python3
import sys, yaml, json, jsonschema, glob

with open("alert_policy.schema.json") as f:
    schema = json.load(f)

found_error = False
for path in glob.glob("alert_policies/*.yaml"):
    with open(path) as f:
        docs = list(yaml.safe_load_all(f))
    for i, doc in enumerate(docs):
        if doc is None:
            continue
        try:
            jsonschema.validate(doc, schema)
        except jsonschema.ValidationError as e:
            print(f"❌ Validation error in {path} (doc {i+1}): {e.message}")
            found_error = True
if found_error:
    sys.exit(1)
print("✅ All YAML alert policy files conform to schema.")
