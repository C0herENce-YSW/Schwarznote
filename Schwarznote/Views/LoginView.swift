//
//  LoginView.swift
//  Schwarznote
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthModel.self) private var auth
    @State private var model = QRLoginModel()
    @State private var attempt = 0

    var body: some View {
        @Bindable var auth = auth

        HStack(spacing: 120) {
            qrPanel
                .frame(width: 520, height: 520)

            VStack(alignment: .leading, spacing: 36) {
                Text("Schwarznote")
                    .font(.largeTitle.bold())
                Text("打开手机上的小红书 App，扫描左侧二维码登录")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                statusLabel

                Picker("地区", selection: $auth.region) {
                    ForEach(XHSRegion.allCases) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .frame(maxWidth: 700)

                TextField("签名服务地址，例如 http://192.168.1.10:8790", text: $auth.signerURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 700)
                SecureField("签名服务口令（可选）", text: $auth.signerToken)
                    .frame(maxWidth: 700)

                if case .failed = model.phase {
                    Button("重试") { attempt += 1 }
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
        }
        .padding(80)
        // Restart the flow on retry or when the region or signer (and therefore the client) changes.
        .task(id: "\(attempt)-\(auth.region.rawValue)-\(auth.signerURL)-\(auth.signerToken)") {
            await model.run(auth: auth)
        }
    }

    @ViewBuilder
    private var qrPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(.white)
            switch model.phase {
            case .loading:
                ProgressView()
                    .tint(.black)
            case .showing(let ticket, let status):
                QRCodeImage(content: ticket.url)
                    .padding(36)
                    .opacity(status == .scanned ? 0.25 : 1)
                if status == .scanned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(.green)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.phase {
        case .loading:
            Label("正在生成二维码…", systemImage: "hourglass")
        case .showing(_, let status):
            switch status {
            case .waitingForScan:
                Label("等待扫码", systemImage: "qrcode.viewfinder")
            case .scanned:
                Label("已扫码，请在手机上确认登录", systemImage: "iphone")
            case .confirmed:
                Label("登录中…", systemImage: "person.crop.circle.badge.checkmark")
            case .expired:
                Label("二维码已过期，正在刷新…", systemImage: "arrow.clockwise")
            case .unknown(let raw):
                Label("未知状态（\(raw)）", systemImage: "questionmark.circle")
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.orange)
        }
    }
}
