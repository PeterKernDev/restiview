import sys, io, json
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
from docx import Document

doc = Document(sys.argv[1])
data = []
for i, para in enumerate(doc.paragraphs):
    runs = [{'text': r.text, 'bold': r.bold, 'underline': r.underline} for r in para.runs]
    data.append({'idx': i, 'style': para.style.name, 'full_text': para.text, 'runs': runs})

with open(r'C:\dev\RestiView2\restiview\doc_v3.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('Done. Paragraphs:', len(data))
