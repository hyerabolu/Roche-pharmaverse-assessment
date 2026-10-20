# Q4: Clinical Trial Data Agent  (Prompt -> Parse -> Execute)
import json
import os
import pandas as pd

# Schema: describes the AE columns to the LLM
SCHEMA = {
    "AESEV":  "Severity or intensity of the AE (MILD, MODERATE, SEVERE)",
    "AETERM": "Specific AE or condition (e.g. HEADACHE, DIZZINESS)",
    "AESOC":  "Body system (e.g. CARDIAC DISORDERS, SKIN AND SUBCUTANEOUS TISSUE DISORDERS)",
}


def build_prompt(question):
    """Prompt: give the LLM the schema and ask for JSON."""
    columns = "\n".join(f"- {col}: {desc}" for col, desc in SCHEMA.items())
    return (f"Columns:\n{columns}\n"
            f"Question: {question}\n"
            'Reply only with JSON: {"target_column": "...", "filter_value": "..."}')


def mock_llm(question):
    """Mock LLM reply (no API key). Returns JSON like a real LLM would."""
    q = question.upper().replace("?", "").replace(".", "")
    for sev in ["MILD", "MODERATE", "SEVERE"]:
        if sev in q:
            return json.dumps({"target_column": "AESEV", "filter_value": sev})
    for system in ["CARDIAC", "SKIN", "NERVOUS", "GASTROINTESTINAL"]:
        if system in q:
            return json.dumps({"target_column": "AESOC", "filter_value": system})
    last_word = q.split()[-1]          # e.g. "HEADACHE"
    return json.dumps({"target_column": "AETERM", "filter_value": last_word})


def call_llm(question):
    """Use OpenAI if a key is set, otherwise the mock."""
    prompt = build_prompt(question)
    if os.getenv("OPENAI_API_KEY"):
        from openai import OpenAI
        reply = OpenAI().chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}])
        return reply.choices[0].message.content
    return mock_llm(question)


class ClinicalTrialDataAgent:
    def __init__(self, ae):
        self.ae = ae

    def ask(self, question):
        reply = call_llm(question)                     # Prompt
        result = json.loads(reply)                     # Parse
        col = result["target_column"]
        value = result["filter_value"]
        hits = self.ae[self.ae[col].str.contains(value, case=False, na=False)]   # Execute
        ids = sorted(hits["USUBJID"].unique())
        return col, value, len(ids), ids


# ---- Test: 3 example questions ----
if __name__ == "__main__":
    folder = os.path.dirname(os.path.abspath(__file__))
    ae = pd.read_csv(os.path.join(folder, "adae.csv"))
    agent = ClinicalTrialDataAgent(ae)

    for q in ["Give me the subjects who had Adverse events of Moderate severity.",
              "Which subjects had Headache?",
              "How many patients had cardiac problems?"]:
        col, value, n, ids = agent.ask(q)
        print("Q:", q)
        print("   Mapped to:", col, "=", value)
        print("   Unique subjects:", n)
        print("   First 5 IDs:", ids[:5], "\n")
