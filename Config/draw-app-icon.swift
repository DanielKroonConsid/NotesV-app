import AppKit
import CoreGraphics

// Draws the NotesV icon on a 1024 canvas: the macOS layout is an 824 pt body with a 100 pt margin.
func superellipse(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.setShouldAntialias(true)

    // Body with the system-style drop shadow. The icon itself is the sheet of paper.
    let body = superellipse(CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0.3))
    ctx.addPath(body); ctx.setFillColor(color(0xFBFAF6)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    gradient(ctx, [color(0xFFFFFF), color(0xF1EEE6)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

    // The yellow band, with a soft edge instead of a perforation.
    let bandBottom: CGFloat = 716
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x7A5200, 0.28))
    ctx.setFillColor(color(0xF9C21A))
    ctx.fill(CGRect(x: 0, y: bandBottom, width: 1024, height: 324))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: bandBottom, width: 1024, height: 324))
    gradient(ctx, [color(0xFFDD55), color(0xF7B500)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: bandBottom))
    ctx.restoreGState()

    // Two short text lines, like a few meeting bullets.
    ctx.setStrokeColor(color(0xBDB8AB)); ctx.setLineCap(.round); ctx.setLineWidth(26)
    for (y, end) in [(CGFloat(628), CGFloat(700)), (558, CGFloat(560))] {
        ctx.move(to: CGPoint(x: 214, y: y)); ctx.addLine(to: CGPoint(x: end, y: y)); ctx.strokePath()
    }

    // The checkmark, which also reads as the V in NotesV.
    let check = CGMutablePath()
    check.move(to: CGPoint(x: 366, y: 366))
    check.addLine(to: CGPoint(x: 462, y: 236))
    check.addLine(to: CGPoint(x: 660, y: 476))
    ctx.addPath(check)
    ctx.setLineWidth(70); ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    gradient(ctx, [color(0xF9A11B), color(0xE5620F)], from: CGPoint(x: 512, y: 500), to: CGPoint(x: 512, y: 200))
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
for size in [16, 32, 48, 64, 128, 256, 512, 1024] {
    try render(size: size).write(to: URL(filePath: "\(out)/icon_\(size).png"))
}
