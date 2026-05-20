import SwiftUI

struct MainView: View {
    @State private var viewModel = SnifferViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // ステータス表示
            HStack {
                Circle()
                    .fill(viewModel.isCapturing ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(viewModel.statusMessage)
                    .font(.headline)
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
            .padding(.bottom, 20)
        }
        .frame(width: 350, height: 350)
        .padding()
    }
}

#Preview {
    MainView()
}
