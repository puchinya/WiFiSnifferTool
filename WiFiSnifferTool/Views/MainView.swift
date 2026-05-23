import SwiftUI

struct MainView: View {
    @State private var viewModel = SnifferViewModel()
    
    var body: some View {
        VStack(spacing: 15) { // 終了ボタンが入るため spacing を少し詰めました
            // ステータス表示
            VStack(spacing: 5) {
                HStack {
                    Circle()
                        .fill(viewModel.isCapturing ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(viewModel.statusMessage)
                        .font(.headline)
                }
                
                if viewModel.requiresApproval {
                    Button(action: {
                        viewModel.openSystemSettings()
                    }) {
                        Label("システム設定を開く", systemImage: "arrow.up.forward.square")
                            .font(.subheadline)
                    }
                    .buttonStyle(.link)
                    .foregroundColor(.blue)
                }
            }
            .padding(.top, 10)
            
            Divider()
            
            // 設定フォーム
            Form {
                Picker("インターフェース:", selection: $viewModel.selectedInterface) {
                    ForEach(viewModel.availableInterfaces, id: \.self) { interface in
                        Text(interface).tag(interface)
                    }
                }
                .disabled(viewModel.isCapturing)
                
                Picker("チャンネル:", selection: $viewModel.selectedChannel) {
                    ForEach(viewModel.availableChannels, id: \.self) { ch in
                        Text("\(ch)").tag(ch)
                    }
                }
                .disabled(viewModel.isCapturing || viewModel.availableChannels.isEmpty)
                
                Picker("チャンネル幅:", selection: $viewModel.selectedChannelWidth) {
                    ForEach(viewModel.availableWidths, id: \.self) { width in
                        Text("\(width) MHz").tag(width)
                    }
                }
                .disabled(viewModel.isCapturing || viewModel.availableWidths.isEmpty)
                
                TextField("出力先パイプ:", text: $viewModel.outputPipePath)
                    .disabled(viewModel.isCapturing)
            }
            .padding(.horizontal)
            
            // コントロールボタン
            HStack(spacing: 30) {
                Button(action: {
                    if viewModel.isCapturing {
                        viewModel.stopCapture()
                    } else {
                        viewModel.startCapture()
                    }
                }) {
                    Text(viewModel.isCapturing ? "停止" : "キャプチャ開始")
                        .fontWeight(.bold)
                        .frame(width: 120, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isCapturing ? .red : .blue)
            }
            
            Divider()
            
            // アプリ終了ボタン（トレイ型アプリに必須の脱出経路）
            HStack {
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("WiFi Sniffer を終了")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain) // 悪目立ちしないシンプルなテキストボタンに
            }
            .padding(.horizontal)
            .padding(.bottom, 5)
        }
        .frame(width: 350, height: 380) // 終了ボタンの分、高さを少しだけ広げました
        .padding()
    }
}

#Preview {
    MainView()
}
