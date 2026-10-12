// Generates the bundled demo source "Endocrine Basics" — a short textbook-style chapter organized
// by organ (as most textbooks are), with a real PDF outline so the Collect step can extract it.
// Usage: swift tools/make_demo_pdf.swift ReMap/Resources/Demo/EndocrineBasics.pdf
import AppKit
import PDFKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "EndocrineBasics.pdf")
let page = CGRect(x: 0, y: 0, width: 595, height: 842)

struct Section { let title: String; let level: Int; let body: String }
// Facts are physiologically correct (insulin ↓ glucose, glucagon ↑; calcitonin ↓ Ca²⁺, PTH ↑ Ca²⁺).
let pages: [[Section]] = [
    [Section(title: "Hormones", level: 0, body: "Hormones are chemical messengers released into the blood by endocrine glands. They travel to target cells that carry matching receptors, and change what those cells do. This chapter walks through the major glands one by one.")],
    [Section(title: "Pancreas", level: 0, body: "Besides its digestive role, the pancreas contains clusters of endocrine cells called the islets of Langerhans."),
     Section(title: "Insulin", level: 1, body: "Insulin is released after a meal when blood glucose rises. It helps muscle, fat and liver cells take up glucose, lowering blood sugar."),
     Section(title: "Glucagon", level: 1, body: "Glucagon is released when blood glucose falls. It tells the liver to break down glycogen and release glucose, raising blood sugar.")],
    [Section(title: "Beta cells", level: 1, body: "Beta cells in the islets sense glucose directly and secrete insulin. Alpha cells secrete glucagon. In type 1 diabetes, beta cells are destroyed by the immune system.")],
    [Section(title: "Adrenal glands", level: 0, body: "The two adrenal glands sit on top of the kidneys. Their inner medulla and outer cortex release different hormones."),
     Section(title: "Adrenaline", level: 1, body: "Adrenaline (epinephrine) from the medulla drives the fast fight-or-flight response: heart rate rises, airways open and glucose is released within seconds.")],
    [Section(title: "Cortisol", level: 1, body: "Cortisol from the cortex shapes the slower, long-term stress response. It raises blood glucose over hours, suppresses inflammation, and when chronically high it weakens bone.")],
    [Section(title: "Thyroid gland", level: 0, body: "The thyroid in the neck sets the body's metabolic rate with thyroxine (T4) and triiodothyronine (T3)."),
     Section(title: "Calcitonin", level: 1, body: "Calcitonin, made by the thyroid's C cells, lowers blood calcium by slowing the cells that break down bone.")],
    [Section(title: "Parathyroid glands", level: 0, body: "Four tiny parathyroid glands sit behind the thyroid."),
     Section(title: "Parathormone", level: 1, body: "Parathyroid hormone (parathormone) raises blood calcium: it releases calcium from bone, keeps it in the kidneys and activates vitamin D.")],
    [Section(title: "Negative feedback", level: 0, body: "Most hormones are controlled by negative feedback: when a value drifts, a hormone pushes it back, and when it is restored the signal stops — like a thermostat.")],
]

let data = NSMutableData()
var box = page
let consumer = CGDataConsumer(data: data as CFMutableData)!
let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let ink = NSColor(red: 0.17, green: 0.18, blue: 0.15, alpha: 1)
func draw(_ text: String, font: NSFont, color: NSColor = ink, at y: inout CGFloat, width: CGFloat = 475) {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 4
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let bounds = attributed.boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
    attributed.draw(with: CGRect(x: 60, y: y - bounds.height, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
    y -= bounds.height + 14
}

var headingPositions: [(page: Int, title: String, level: Int, y: CGFloat)] = []
for (index, sections) in pages.enumerated() {
    ctx.beginPDFPage(nil)
    NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill(); NSBezierPath(rect: page).fill()
    var y = page.height - 70
    var footer = page.height - 40
    draw("Endocrine Basics · Chapter 4", font: .systemFont(ofSize: 9, weight: .medium), color: .gray, at: &footer)
    for section in sections {
        headingPositions.append((index, section.title, section.level, y))
        draw(section.title, font: section.level == 0 ? .boldSystemFont(ofSize: 26) : .boldSystemFont(ofSize: 17), at: &y)
        draw(section.body, font: .systemFont(ofSize: 12), at: &y)
        y -= 10
    }
    var pageNumber: CGFloat = 50
    draw("\(index + 1)", font: .systemFont(ofSize: 9), color: .gray, at: &pageNumber)
    ctx.endPDFPage()
}
ctx.closePDF()

// Add the outline (table of contents) with PDFKit.
let document = PDFDocument(data: data as Data)!
let root = PDFOutline()
var currentTop: PDFOutline?
for heading in headingPositions {
    let item = PDFOutline()
    item.label = heading.title
    if let p = document.page(at: heading.page) {
        item.destination = PDFDestination(page: p, at: CGPoint(x: 60, y: heading.y))
    }
    if heading.level == 0 || currentTop == nil {
        root.insertChild(item, at: root.numberOfChildren)
        currentTop = item
    } else {
        currentTop!.insertChild(item, at: currentTop!.numberOfChildren)
    }
}
document.outlineRoot = root
document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Endocrine Basics", PDFDocumentAttribute.authorAttribute: "ReMap demo"]
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
document.write(to: out)
print("wrote \(out.path) with \(document.pageCount) pages")
