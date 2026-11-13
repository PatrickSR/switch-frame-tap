// SPDX-License-Identifier: GPL-2.0-only
import SwiftUI

struct HomeView: View {
    @Environment(StreamSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    private var portValid: Bool {
        settings.port >= 1 && settings.port <= 65535
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Switch 串流")
                    .font(.largeTitle.bold())
                    .padding(.top, 12)

                VStack(spacing: 12) {
                    TextField("Switch 地址（局域网 IP）", text: Bindable(settings).host)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)

                    HStack {
                        Text("端口")
                        TextField("9950", value: Bindable(settings).port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 110)
                        Spacer()
                    }

                    Button("连接") {
                        session.start(host: settings.host, port: settings.port)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(settings.host.trimmingCharacters(in: .whitespaces).isEmpty || !portValid)

                    if let error = session.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                DisclosureGroup("Switch 端设置检查") {
                    VStack(alignment: .leading, spacing: 8) {
                        checkItem("Connection 设为 Network")
                        checkItem("远程建议 Quality = Medium、Max resolution = 720")
                        checkItem("Beta 页开启 Stream the HOME menu 和 Controls from the viewer")
                        checkItem("改完重启 Switch")
                        checkItem("系统设置里关闭自动睡眠")
                        checkItem("建议插底座并用有线网卡")
                        checkItem("iPhone 开启 Tailscale，地址填 Switch 的局域网 IP")
                        checkItem("同一时间只能一个播放器连接")
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                Button("设置") {
                    showSettings = true
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showDisconnect: false)
        }
    }

    private func checkItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}
