import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.29, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 215, yRadius: 215).fill()
NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 235, y: 170, width: 554, height: 684), xRadius: 45, yRadius: 45).fill()
NSColor(calibratedRed: 0.24, green: 0.43, blue: 0.35, alpha: 1).setStroke()
let path = NSBezierPath(); path.lineWidth = 37; path.lineCapStyle = .round; path.lineJoinStyle = .round
path.move(to: NSPoint(x: 337, y: 510)); path.line(to: NSPoint(x: 337, y: 691)); path.line(to: NSPoint(x: 435, y: 575)); path.line(to: NSPoint(x: 531, y: 691)); path.line(to: NSPoint(x: 531, y: 510)); path.stroke()
let arrow = NSBezierPath(); arrow.lineWidth = 28; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 659, y: 691)); arrow.line(to: NSPoint(x: 659, y: 519)); arrow.move(to: NSPoint(x: 611, y: 561)); arrow.line(to: NSPoint(x: 659, y: 511)); arrow.line(to: NSPoint(x: 707, y: 561)); arrow.stroke()
NSColor(calibratedRed: 0.69, green: 0.76, blue: 0.69, alpha: 1).setFill()
for (y, width) in [(398.0, 365.0), (316.0, 270.0)] { NSBezierPath(roundedRect: NSRect(x: 329, y: y, width: width, height: 24), xRadius: 12, yRadius: 12).fill() }
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
