import Foundation

/// Synthetic display samples only. No user audio/text, no arbitrary payloads.
struct DisplayBoundaryFixture {
    let id: String
    let name: String
    let text: String
    static let all: [Self] = [
        .init(id:"D01", name:"短文字基线", text:"D01 显示边界测试 123 ABC 结束"),
        .init(id:"D02", name:"三行换行", text:"D02 第一行 开始\n第二行 ABC 123\n第三行 结束"),
        .init(id:"D03", name:"中英符号混排", text:"D03 中文 ABC abc 0123456789\n标点：，。！？()[]+-=/\n结束"),
        .init(id:"D04", name:"特殊字形", text:"D04 字形测试\n箭头 ↑↓←→ 勾 ✓ 星 ★\n表情 🙂 中文结束"),
        .init(id:"D05", name:"八行裁切", text:(1...8).map { "D05 第\($0)行 ABC 中文" }.joined(separator:"\n") + "\nEND05"),
        .init(id:"D06", name:"长英文折行", text:"D06 " + String(repeating:"ABCDEFGHIJ0123456789", count:8) + " END06"),
        .init(id:"D07", name:"长中文折行", text:"D07 " + String(repeating:"一二三四五六七八九十", count:12) + " END07"),
    ]
}
