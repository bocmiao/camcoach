// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 入口。数据在启动时解码一次，失败就直接说清楚，
/// 不做「空列表」这种看不出是坏了还是没内容的降级。
struct RootView: View {

    var body: some View {
        switch CameraDataStore.shared {
        case .success(let data):
            MainTabs(data: data)
        case .failure(let error):
            DataErrorView(message: error.localizedDescription)
        }
    }
}

struct MainTabs: View {

    let data: CameraData

    var body: some View {
        TabView {
            NavigationStack {
                LiveViewScreen(data: data)
            }
            .tabItem {
                Label("取景", systemImage: "camera.viewfinder")
            }

            NavigationStack {
                BodyDiagramView(data: data)
            }
            .tabItem {
                Label("看按键", systemImage: "camera.metering.center.weighted")
            }

            NavigationStack {
                MenuSearchView(data: data)
            }
            .tabItem {
                Label("找设置", systemImage: "magnifyingglass")
            }

            NavigationStack {
                PresetListView(data: data)
            }
            .tabItem {
                Label("拍什么", systemImage: "slider.horizontal.3")
            }

            NavigationStack {
                ChecklistView(data: data)
            }
            .tabItem {
                Label("上手", systemImage: "checklist")
            }
        }
    }
}

struct DataErrorView: View {

    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("内容没加载出来")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("这通常是打包时 camcoach-data.json 没进 App。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
