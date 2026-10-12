"""Behavior check for Foundation/CoreGraphics models on this Mac's older Swift.
Only strips Swift 6 type-isolation modifiers in disposable copies. NOT an iOS build.
"""
from pathlib import Path
import tempfile,subprocess,re,json
root=Path(__file__).resolve().parents[1]
files=['Model/Headline.swift','Model/MindMap.swift','Model/StudySession.swift','Services/TrainingLLMContent.swift']
with tempfile.TemporaryDirectory(prefix='remap-model-check-') as tmp:
    out=Path(tmp)
    for rel in files:
        text=(root/'ReMap'/rel).read_text()
        text=re.sub(r'\bnonisolated (?=(?:struct|enum|class))','',text)
        (out/Path(rel).name).write_text(text)
    # MindMap bounds uses the designer's small CGRect.center convenience.
    (out/'main.swift').write_text(r'''
import Foundation
import CoreGraphics
extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
var session = StudySession(title: "Training an LLM", source: SourceInfo(kind: .demo, name: "TrainingLLM.pdf"), headlines: TrainingLLMContent.headlines(), map: MindMap(title: "Training an LLM"))
check(session.headlines.count == 12, "all 12 source keywords")
check(!session.canBeginBackbone, "unlabeled collection cannot start")
for i in session.headlines.indices { session.headlines[i].role = i < 3 ? .backbone : .topic }
check(session.canBeginBackbone, "3 backbone, many topics")
session.phase = .backbone
session.reachedPhases[.backbone] = Date()
check(!session.canAssignRole(.backbone, to: session.headlines[3].id), "cannot expand committed backbone")
check(!session.canAssignRole(.topic, to: session.headlines[0].id), "cannot drop committed backbone")
session.map.title = session.headlines[0].text
check(session.unplacedHeadlines.contains { $0.id == session.headlines[0].id }, "title cannot hide required keyword")
check(session.unplacedHeadlines.count == 3, "only backbone in initial tray")
for h in session.backboneKeywords { session.map.nodes.append(MapNode(label: h.text, position: .zero, isBackbone: true, headlineID: h.id)) }
check(session.missingBackboneKeywords.isEmpty, "all required identities represented")
session.map.nodes.removeLast()
check(session.missingBackboneKeywords.count == 1, "missing backbone stays required")
for i in 3..<6 { session.headlines[i].role = .backbone }
check(!session.canBeginBackbone, "6 backbone invalid")
session.headlines[5].role = .detail
check(session.canBeginBackbone, "5 backbone allowed")
session.phase = .details
check(session.unplacedHeadlines.contains { $0.role == .detail }, "details remain available later")
let data = try JSONEncoder().encode(session)
let restored = try JSONDecoder().decode(StudySession.self, from: data)
check(restored == session, "save restore preserves keyword identity and drawing")
var legacy = session; legacy.source.name = "EndocrineBasics.pdf"
check(!legacy.usesLocalCoach, "existing designer source remains separate")
check(SessionPhase.details.rawValue == 4, "saved phase compatibility")
var pdf = session
var legacyPDF = pdf
legacyPDF.source = SourceInfo(kind: .pdf, name: "Older import.pdf", fileName: "older.pdf")
check(!legacyPDF.usesLocalCoach && !legacyPDF.needsSourceUpload, "older PDF sessions keep the cloud coach until re-uploaded")
pdf.source = SourceInfo(kind: .pdf, name: "A different lecture.pdf", fileName: "local.pdf", usesLearningEngine: true)
check(pdf.usesLocalCoach && pdf.needsSourceUpload, "pending imported PDF must never select legacy coach")
check(pdf.localCoachSourceID == nil && pdf.localSourcePageCount == 0, "pending PDF cannot use demo identity or pages")
pdf.source.sourceId = "pdf-" + String(repeating: "a", count: 64)
pdf.source.pageCount = 4
check(!pdf.needsSourceUpload && pdf.localCoachSourceID == pdf.source.sourceId, "registered PDF uses own identity")
check(pdf.localSourcePageCount == 4, "imported citations use actual page bound")
let pdfRoundTrip = try JSONDecoder().decode(StudySession.self, from: JSONEncoder().encode(pdf))
check(pdfRoundTrip == pdf, "PDF source identity and page count survive session persistence")
let oldSource = try JSONDecoder().decode(SourceInfo.self, from: Data(#"{"kind":"pdf","name":"Old lecture.pdf","fileName":"old.pdf"}"#.utf8))
check(oldSource.sourceId == nil && oldSource.pageCount == nil, "old saved sources decode without new keys")
check(session.localCoachSourceID == "training-llm" && session.localSourcePageCount == 18, "bundled demo keeps original identity")
var olderPDF = pdf
for i in olderPDF.headlines.indices { olderPDF.headlines[i].role = i < 2 ? .backbone : .topic }
check(!olderPDF.canBeginBackbone, "legacy two-keyword backbone needs repair")
check(olderPDF.canAssignRole(.backbone, to: olderPDF.headlines[2].id), "legacy PDF can add missing third backbone")
check(!olderPDF.canAssignRole(.topic, to: olderPDF.headlines[0].id) && olderPDF.isCommittedBackbone(olderPDF.headlines[0].id), "repair never unlocks committed keywords")
olderPDF.headlines[2].role = .backbone
check(olderPDF.canBeginBackbone, "repair reaches valid backbone")
check(!olderPDF.canAssignRole(.backbone, to: olderPDF.headlines[3].id), "valid committed backbone stops expanding")
print("28 native model assertions passed (Swift5 compatibility copies; no UIKit build).")
''')
    result=subprocess.run(['swiftc',*map(str,out.glob('*.swift')),'-o',str(out/'check')],capture_output=True,text=True)
    if result.returncode: print(result.stderr);raise SystemExit(result.returncode)
    subprocess.run([str(out/'check')],check=True)
