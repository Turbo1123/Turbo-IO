import AppKit
let directory = CommandLine.arguments[1]
let width = 54, height = 106
var header = "// Rasterized system monospaced digits at 84 px, one bit per pixel.\nstatic const unsigned char tw_glyphs[11][716]={\n"
for char in Array("0123456789-") {
 let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width*4, bitsPerPixel: 32)!
 NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
 NSColor.black.setFill(); NSRect(x: 0,y:0,width:width,height:height).fill()
 let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:84,weight:.semibold),.foregroundColor:NSColor.white]
 let text = String(char); let size = text.size(withAttributes:attributes)
 text.draw(at: NSPoint(x:(Double(width)-size.width)/2, y:(Double(height)-size.height)/2),withAttributes:attributes)
 NSGraphicsContext.restoreGraphicsState()
 var bytes=[UInt8](repeating:0,count:(width*height+7)/8)
 for y in 0..<height { for x in 0..<width { let c=rep.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!; if c.redComponent>0.42 { let i=y*width+x; bytes[i/8] |= 1 << (7-i%8) } } }
 header += "{"+bytes.map(String.init).joined(separator:",")+"},\n"
}
header += "};\n"
try header.write(toFile:directory+"/workout_glyphs.h",atomically:true,encoding:.utf8)
