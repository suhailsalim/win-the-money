import AppKit

// Generates the three adaptive 1024 app-icon variants (light / dark / tinted)
// into Assets.xcassets/AppIcon.appiconset. Run:  swift design/GenerateIcons.swift
// Art is flat & full-bleed; iOS 26 applies the Liquid Glass treatment itself.

enum Style { case light, dark, tinted }

func draw(_ style: Style, to path: String) {
    let S = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    let sz = CGFloat(S)
    let cs = CGColorSpaceCreateDeviceRGB()

    // background
    switch style {
    case .light:
        let grad = CGGradient(colorsSpace: cs, colors: [
            CGColor(red: 0.431, green: 0.608, blue: 0.847, alpha: 1),   // blue
            CGColor(red: 0.498, green: 0.769, blue: 0.639, alpha: 1)] as CFArray, // green
            locations: [0, 1])!
        g.drawLinearGradient(grad, start: CGPoint(x: 0, y: sz), end: CGPoint(x: sz, y: 0), options: [])
    case .dark:
        let grad = CGGradient(colorsSpace: cs, colors: [
            CGColor(red: 0.071, green: 0.094, blue: 0.125, alpha: 1),
            CGColor(red: 0.063, green: 0.110, blue: 0.090, alpha: 1)] as CFArray, locations: [0, 1])!
        g.drawLinearGradient(grad, start: CGPoint(x: 0, y: sz), end: CGPoint(x: sz, y: 0), options: [])
    case .tinted:
        g.clear(CGRect(x: 0, y: 0, width: sz, height: sz))   // transparent; system applies tint
    }

    // glyph: a leaf + ₹, drawn in white (light/dark) or light gray (tinted, monochrome)
    let glyphColor: NSColor
    switch style {
    case .light, .dark: glyphColor = .white
    case .tinted:       glyphColor = NSColor(white: 0.92, alpha: 1)
    }
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 560, weight: .heavy),
        .foregroundColor: glyphColor, .paragraphStyle: p]
    let s = NSAttributedString(string: "₹", attributes: attrs)
    let r = s.boundingRect(with: NSSize(width: sz, height: sz), options: .usesLineFragmentOrigin)
    s.draw(in: NSRect(x: 0, y: (sz - r.height)/2 - 30, width: sz, height: r.height))

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let base = "/Users/suhailaka/win the money/WinTheMoney/Assets.xcassets/AppIcon.appiconset"
draw(.light,  to: "\(base)/icon-light-1024.png")
draw(.dark,   to: "\(base)/icon-dark-1024.png")
draw(.tinted, to: "\(base)/icon-tinted-1024.png")
