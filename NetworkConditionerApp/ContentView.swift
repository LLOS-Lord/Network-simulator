import SwiftUI

struct ContentView: View {
    @StateObject private var manager = ConditionerManager()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    statusRow
                }

                Section("VPN") {
                    Button(manager.isConnected ? "Ngắt kết nối" : "Bắt đầu") {
                        Task {
                            if manager.isConnected {
                                manager.stop()
                            } else {
                                await manager.start()
                            }
                        }
                    }
                    .tint(manager.isConnected ? .red : .accentColor)
                }

                Section {
                    Toggle("Bật giả lập điều kiện mạng", isOn: $manager.profile.isEnabled)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mất gói (packet loss): \(Int(manager.profile.packetLossPercent))%")
                        Slider(value: $manager.profile.packetLossPercent, in: 0...100, step: 1)
                    }
                    .disabled(!manager.profile.isEnabled)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Độ trễ (delay): \(Int(manager.profile.delayMilliseconds)) ms")
                        Slider(value: $manager.profile.delayMilliseconds, in: 0...3000, step: 10)
                    }
                    .disabled(!manager.profile.isEnabled)
                } header: {
                    Text("Cấu hình mạng")
                } footer: {
                    Text("Thay đổi áp dụng ngay lập tức cho VPN đang chạy, không cần ngắt kết nối. Áp dụng đồng đều cho toàn bộ traffic — không lọc theo loại gói hay kích thước.")
                }
            }
            .navigationTitle("Network Conditioner")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(manager.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
