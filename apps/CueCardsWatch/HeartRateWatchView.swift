import SwiftUI

struct HeartRateWatchView: View {
    @ObservedObject var model: HeartRateModel
    private func value(_ metric: LiveWorkoutMetric?, at now: Date, format: String) -> String {
        guard !model.isPaused, let metric, metric.fresh(at: now) else { return "—" }
        return String(format: format, metric.value)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let freshHeart = !model.isPaused && (model.heart?.fresh(at: context.date) ?? false)
                    HStack(alignment: .firstTextBaseline) {
                        Text(value(model.heart, at: context.date, format: "%.0f")).font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(.red)
                        Text("次/分").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(freshHeart ? model.zoneLabel : "—").font(.title3.bold())
                    }.monospacedDigit()
                    if model.zoneCount > 0 {
                        HStack(spacing: 3) {
                            ForEach(1...model.zoneCount, id: \.self) { zone in
                                Capsule().fill(freshHeart && model.zonePosition == zone ? Color.green : Color.gray.opacity(0.3)).frame(height: 6)
                            }
                        }
                    }
                    if model.mode != .heartRate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前配速 /公里").font(.caption2).foregroundStyle(.secondary)
                            Text(paceText(at: context.date)).font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(.green).monospacedDigit()
                        }
                        HStack {
                            metricCell("步频 · 步/分", value: value(model.cadence, at: context.date, format: "%.0f"))
                            Spacer()
                            metricCell("步幅 · 米", value: value(model.stride, at: context.date, format: "%.2f"))
                        }
                        Text("活动热量 \(model.energy.map { String(format: "%.0f", $0.value) } ?? "—") kcal").font(.caption2).monospacedDigit()
                        HStack {
                            Text("距离 \(distanceText(at: context.date)) km")
                            Spacer()
                            Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                        }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(model.zoneNote).font(.caption2).foregroundStyle(.secondary)
                Text(model.note).font(.caption2).foregroundStyle(.secondary)
                if model.isRunning {
                    Button(model.isPaused ? "继续跑步" : "暂停") { model.pauseOrResume() }.disabled(model.isBusy)
                    Button("结束并保存") { model.stop(reason: "结束并保存") }.tint(.red).disabled(model.isBusy)
                } else if model.saveFailed {
                    Button("重试保存") { model.retrySave() }.tint(.orange)
                } else {
                    Button("开始室外跑步") { model.start() }.tint(.green).disabled(model.isBusy)
                }
                if !model.isRunning {
                    Text("请先结束其他体能训练。手机可锁屏，手表继续记录；结束时保存为室外跑步。步频由 HealthKit 步数计算，跑动后才会产生配速与步幅。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 4)
        }
        .navigationTitle("运动看板")
    }
    private func metricCell(_ title: String, value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.title3.bold()).monospacedDigit() }
    }
    private func paceText(at now: Date) -> String {
        guard !model.isPaused, let pace = model.pace, pace.fresh(at: now) else { return "—" }
        let seconds = Int(pace.value.rounded()); return String(format: "%d′%02d″", seconds / 60, seconds % 60)
    }
    private func distanceText(at now: Date) -> String {
        guard let distance = model.distance else { return "—" }
        return String(format: "%.2f", distance.value / 1000)
    }
}
