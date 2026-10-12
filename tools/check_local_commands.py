"""Compile/run production command validation with a minimal in-memory SessionModel harness.
Swift6 type-isolation modifiers removed only in temp compatibility copies. No iOS build claim.
"""
from pathlib import Path
import tempfile,subprocess,re
root=Path(__file__).resolve().parents[1]
files=['Model/Headline.swift','Model/MindMap.swift','Model/StudySession.swift','Services/TrainingLLMContent.swift','Services/LayoutEngine.swift','Services/MapRules.swift','Features/Coach/CoachMapCommand.swift','Services/LocalCoachPayload.swift']
with tempfile.TemporaryDirectory(prefix='remap-command-check-') as tmp:
 out=Path(tmp)
 for rel in files:
  text=(root/'ReMap'/rel).read_text()
  if rel.endswith('LocalCoachPayload.swift'): text=text.split('extension SessionModel {')[0]
  text=re.sub(r'\bnonisolated (?=(?:struct|enum|class|extension))','',text)
  (out/Path(rel).name).write_text(text)
 (out/'main.swift').write_text(r'''
import Foundation
import CoreGraphics
class SessionModel {
 var session: StudySession
 var map: MindMap { session.map }
 var mapRevision = UUID()
 struct Selection { var nodeID: UUID?; var edgeID: UUID?; static let none = Self() }
 var selection = Selection.none
 var edits = 0
 var focus: Set<UUID> = []
 var canUndo: Bool { edits > 0 }
 func undo() {}
 func point(at ids: [UUID]) { focus = Set(ids) }
 init(_ session: StudySession) { self.session = session }
 func editMap(_ update: (inout MindMap) -> Void) { update(&session.map); edits += 1; mapRevision = UUID() }
}
enum LocalCoachFailure: Error { case message(String) }
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
var session = StudySession(title: "Training an LLM", source: SourceInfo(kind: .demo, name: "TrainingLLM.pdf"), headlines: TrainingLLMContent.headlines(), map: MindMap(title: "Training an LLM"))
session.headlines[0].role = .backbone
let backbone = MapNode(label: session.headlines[0].text, position: .zero, isBackbone: false, headlineID: session.headlines[0].id)
let other = MapNode(label: "Evaluation", position: CGPoint(x: 200, y: 200))
session.map.nodes = [backbone,other]
let model = SessionModel(session)
check(model.coachSnapshot.nodes[0].backbone, "committed keyword protected even if emphasis toggled")
let revision = model.mapRevision
let move = CoachMapAction(kind: .moveNode, id: other.id, x: 250, y: 240)
let command = CoachMapCommand(request: "Move Evaluation right", revision: revision, operations: [move])
_ = try model.applyCoachCommand(command, latestRequest: command.request)
check(model.map.node(other.id)?.position.x == 250 && model.edits == 1, "move applies in one transaction")
do { _ = try model.applyCoachCommand(command, latestRequest: command.request); fatalError("stale revision accepted") } catch {}
let before = model.map
let delete = CoachMapCommand(request: "Delete Pretraining", revision: model.mapRevision, operations: [.init(kind: .deleteNode, id: backbone.id)])
do { _ = try model.applyCoachCommand(delete, latestRequest: delete.request); fatalError("committed node deleted") } catch {}
check(model.map == before, "failed command leaves map unchanged")
let edgeID = UUID()
let pair = CoachMapCommand(request: "Connect these and set the reason", revision: model.mapRevision, operations: [
 .init(kind: .connect, id: edgeID, from: backbone.id, to: other.id, reason: ""),
 .init(kind: .setReason, id: edgeID, reason: "Evaluation measures the resulting model.")])
_ = try model.applyCoachCommand(pair, latestRequest: pair.request)
check(model.map.edges[0].id == edgeID && model.map.edges[0].reason.hasPrefix("Evaluation"), "connect ID survives dependent operation")
check(model.edits == 2, "multi-operation command is one undo unit")
let bad = CoachMapCommand(request: "Move Evaluation", revision: model.mapRevision, operations: [move,.init(kind: .moveNode, id: UUID(), x: 10, y: 10)])
let beforeBad = model.map
 do { _ = try model.applyCoachCommand(bad, latestRequest: bad.request); fatalError("bad transaction accepted") } catch {}
check(model.map == beforeBad && model.edits == 2, "invalid operation rolls back entire command")
let json = try JSONEncoder().encode(model.coachSnapshot)
check(!json.isEmpty, "wire DTO encodes")
let reply = try JSONDecoder().decode(LocalCoachReply.self, from: Data("{\"message\":\"Think about the relationship\",\"references\":[{\"page\":7,\"reason\":\"Training stages\"}]}".utf8))
check(reply.command == nil && reply.references[0].page == 7, "ordinary reply decodes without command")
var sourceQuery = try JSONDecoder().decode(LocalSourceQuery.self, from: Data(#"{"query":"What is this relationship?","pages":[2]}"#.utf8))
sourceQuery.sourceId = "pdf-" + String(repeating: "b", count: 64)
let queryJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sourceQuery)) as! [String: Any]
check(queryJSON["sourceId"] as? String == sourceQuery.sourceId, "voice tool payload carries current PDF identity")
let PDFRequest = LocalCoachRequest(sourceId: sourceQuery.sourceId!, message: "Explain this", action: "discuss", session: LocalCoachSession(step: 0, topics: [], selected: [], roles: [:], groups: [], messages: [], page: 2), board: model.coachSnapshot, snapshot: nil)
let requestJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PDFRequest)) as! [String: Any]
check(requestJSON["sourceId"] as? String == sourceQuery.sourceId, "typed and voice session payload carries imported identity")
let processing = try JSONDecoder().decode(LocalPDFUploadResponse.self, from: Data(#"{"jobId":"job-1","status":"processing"}"#.utf8))
check(processing.sourceId == nil && processing.jobId == "job-1" && processing.status == "processing", "async upload job decodes without completed fields")
let complete = try JSONDecoder().decode(LocalPDFUploadResponse.self, from: Data(#"{"sourceId":"pdf-abc","title":"Lecture","pageCount":2,"topics":[{"id":"keyword-1","label":"Photosynthesis","page":1}],"warnings":[]}"#.utf8))
check(complete.jobId == nil && complete.pageCount == 2 && complete.topics?.first?.label == "Photosynthesis", "completed upload decodes without job fields")
let pollJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalPDFJobQuery(jobId: "job-1"))) as! [String: Any]
check(pollJSON["jobId"] as? String == "job-1", "poll sends same job identity without re-uploading PDF")
print("14 native command/DTO assertions passed (Swift5 compatibility copies and SessionModel harness).")
''')
 r=subprocess.run(['swiftc',*map(str,out.glob('*.swift')),'-o',str(out/'check')],capture_output=True,text=True)
 if r.returncode: print(r.stderr);raise SystemExit(r.returncode)
 subprocess.run([str(out/'check')],check=True)
