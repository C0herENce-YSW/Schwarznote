//
//  HomeView.swift
//  Schwarznote
//

import SwiftUI

/// Placeholder after login; the feed comes later.
struct HomeView: View {
    @Environment(AuthModel.self) private var auth
    let user: XHSUser?

    var body: some View {
        VStack(spacing: 40) {
            AsyncImage(url: user?.avatarURL.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, height: 200)
            .clipShape(Circle())

            Text(user?.nickname ?? "已登录")
                .font(.largeTitle.bold())

            if user == nil {
                Text("已恢复登录信息，但暂时无法获取账号资料")
                    .foregroundStyle(.secondary)
            }

            Button("退出登录", role: .destructive) {
                auth.logOut()
            }
        }
    }
}
