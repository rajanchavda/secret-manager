import AppKit
import CoreGraphics

func createDockAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    // Draw macOS Squircle with Shadow
    let margin = size * 0.08
    let squircleRect = CGRect(x: margin, y: margin, width: size - (margin * 2), height: size - (margin * 2))
    let cornerRadius = squircleRect.width * 0.225
    let path = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    
    // Fill Gradient (Emerald Green to Deep Teal)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.10, green: 0.76, blue: 0.50, alpha: 1.0), // #19C280 (green)
        CGColor(red: 0.05, green: 0.58, blue: 0.55, alpha: 1.0)  // #0D948C (teal)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
            options: []
        )
    }
    ctx.restoreGState()
    
    // Subtle Inner Highlight Rim
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
    ctx.setLineWidth(size * 0.015)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Subtle Top Light Glare
    ctx.saveGState()
    let glareRect = CGRect(x: squircleRect.minX, y: squircleRect.midY, width: squircleRect.width, height: squircleRect.height * 0.5)
    let glarePath = CGPath(roundedRect: glareRect, cornerWidth: cornerRadius * 0.8, cornerHeight: cornerRadius * 0.8, transform: nil)
    ctx.addPath(glarePath)
    ctx.clip()
    let glareColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray
    if let glareGrad = CGGradient(colorsSpace: colorSpace, colors: glareColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(glareGrad, start: CGPoint(x: glareRect.midX, y: glareRect.maxY), end: CGPoint(x: glareRect.midX, y: glareRect.minY), options: [])
    }
    ctx.restoreGState()
    
    // Draw Crisp White "lock.shield.fill" Emblem in Center
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
        let symbolImage = NSImage(size: NSSize(width: size, height: size))
        symbolImage.lockFocus()
        NSColor.white.set()
        symbol.draw(at: NSPoint(x: (size - symbol.size.width) / 2.0, y: (size - symbol.size.height) / 2.0 - (size * 0.01)), from: .zero, operation: .sourceOver, fraction: 1.0)
        symbolImage.unlockFocus()
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.035, color: CGColor(red: 0, green: 0.25, blue: 0.2, alpha: 0.45))
        symbolImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        ctx.restoreGState()
    }
    
    image.unlockFocus()
    return image
}

let icon = createDockAppIcon(size: 1024)
guard let tiffData = icon.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("❌ Failed to create PNG representation")
    exit(1)
}

let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let rootDir = URL(fileURLWithPath: scriptDir).deletingLastPathComponent().path
let resourcesDir = "\(rootDir)/Sources/SecApp/Resources"
try? fm.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true, attributes: nil)

let png1024Path = "\(resourcesDir)/icon_1024.png"
try pngData.write(to: URL(fileURLWithPath: png1024Path))

let iconsetDir = "\(resourcesDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetDir)
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true, attributes: nil)

let sizes: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

for (baseSize, scale, name) in sizes {
    let px = baseSize * scale
    let resized = createDockAppIcon(size: CGFloat(px))
    if let rep = NSBitmapImageRep(data: resized.tiffRepresentation!),
       let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
    }
}

// Convert to .icns using macOS iconutil
let icnsPath = "\(resourcesDir)/AppIcon.icns"
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
task.launch()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✅ Successfully generated AppIcon.icns at: \(icnsPath)")
    // Clean up temporary iconset directory
    try? fm.removeItem(atPath: iconsetDir)
} else {
    print("❌ iconutil failed with status: \(task.terminationStatus)")
    exit(1)
}
