import SwiftUI
import UniformTypeIdentifiers
import Sparkle

//update check
class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    var updater: SPUUpdater?
    private let githubAPIURL = "https://api.github.com/repos/nazonoz/pngquant_gui_for_macOS/releases/latest"

    override init() {
        super.init()
        
        let hostBundle = Bundle.main
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)

        updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: userDriver, delegate: self)

        do {
            try updater?.start()
        } catch {
            print("❌ Sparkle 업데이트 시작 오류: \(error.localizedDescription)")
        }
        
        checkForUpdatesFromGitHub() // ✅ 앱 시작 시 자동 업데이트 체크
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    /// 🔥 GitHub API에서 최신 릴리스 정보 가져와서 업데이트 확인
    private func checkForUpdatesFromGitHub() {
        guard let url = URL(string: githubAPIURL) else { return }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("❌ GitHub API 요청 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let latestVersion = json["tag_name"] as? String {  // GitHub에서 최신 버전 가져오기
                    DispatchQueue.main.async {
                        self.compareVersions(latestVersion: latestVersion)
                    }
                }
            } catch {
                print("❌ JSON 파싱 오류: \(error.localizedDescription)")
            }
        }
        task.resume()
    }

    /// 🔥 현재 버전과 비교하여 자동 업데이트 실행
    private func compareVersions(latestVersion: String) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        print("🔎 현재 버전: \(currentVersion), 최신 버전: \(latestVersion)")

        if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
            print("🚀 새로운 업데이트 발견! 업데이트 진행 중...")
            updater?.checkForUpdates()  // 자동 업데이트 실행
        } else {
            print("✅ 최신 상태입니다.")
        }
    }
}

// MARK: - ScrollWheelView
class ScrollWheelTrackingView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    
    override func scrollWheel(with event: NSEvent) {
        // 디버그: 휠 이벤트 로그 .....왜...안되지?
        print("🌀 scrollWheel event: deltaY=\(event.scrollingDeltaY)")
        super.scrollWheel(with: event)
        onScroll?(event.scrollingDeltaY)
    }
}

//제스쳐뷰
struct TrackpadGestureView: NSViewRepresentable {
    var onPan: (CGSize) -> Void

    class Coordinator: NSObject {
        var onPan: (CGSize) -> Void
        
        init(onPan: @escaping (CGSize) -> Void) {
            self.onPan = onPan
        }
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view) // ✅ 이동 후 원점으로 리셋
            
            DispatchQueue.main.async {
                self.onPan(CGSize(width: translation.x, height: translation.y))
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(onPan: onPan)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

//휠 확대축소
struct ScrollWheelView: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> ScrollWheelTrackingView {
        let view = ScrollWheelTrackingView()
        view.onScroll = onScroll
        return view
    }
    func updateNSView(_ nsView: ScrollWheelTrackingView, context: Context) { }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var selectedFile: URL?
    
    @State private var quality: Double = 50.0
    @State private var colorCount: Double = 128.0
    
    @State private var floyd: Double = 0.5
    @State private var speed: Double = 7
    
    @State private var outputFile: URL?
    @State private var currentSize: String = ""
    @State private var previewImage: NSImage?
    
    @State private var previewScale: CGFloat = 1.0
    @State private var previewPosition: CGSize = .zero
    @State private var lastDragPosition: CGSize = .zero // 마지막 위치 저장
    @State private var previewFile: URL?
    
    @State private var isSettingsTabActive = false
    @State private var isDropTargetActive: Bool = false
    
    @State private var isConverting = false   // 1초 동안 변환 중 메시지
    @State private var showingSaveAlert = false
    @State private var isInterpolationDisabled: Bool = false // 🆕 보간 끄기/켜기 상태
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    //updatecheck
    @StateObject private var updateManager = UpdateManager()
    
    // 포매터 (정수 전용)
    private let qualityFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 10
        f.maximum = 90
        f.allowsFloats = false
        return f
    }()
    private let colorCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 48
        f.maximum = 256
        f.allowsFloats = false
        return f
    }()
    private let floydFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 1
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        f.allowsFloats = true
        return f
    }()
    private let speedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimum = 1
        f.maximum = 11
        f.allowsFloats = false
        return f
    }()
    
    var body: some View {
        VStack {
            if !isSettingsTabActive {
                // 변환 탭
                VStack {
                    ZStack {
                        // 미리보기 배경
                        Color.gray.opacity(0.3)
                            .frame(width: 960, height: 450)
                            .cornerRadius(16)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        previewPosition = CGSize(
                                            width: lastDragPosition.width + value.translation.width,
                                            height: lastDragPosition.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastDragPosition = previewPosition // 마지막 위치 저장
                                    }
                            )
                        
                        if let previewImage = previewImage {
                            Image(nsImage: previewImage)
                                //.resizable()
                                .scaledToFit()
                                .scaleEffect(previewScale)
                                .frame(width: 960, height: 450)
                                .zIndex(1)
                                .offset(x: previewPosition.width, y: previewPosition.height)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            previewPosition = CGSize(
                                                width: lastDragPosition.width + value.translation.width,
                                                height: lastDragPosition.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastDragPosition = previewPosition // 마지막 위치 저장
                                        }
                                )
                                //.interpolation(.none) // ✅ 보간 설정을 토글 값에 따라 적용 .none or .default
                        } else {
                            Text("여기에 파일을 드롭하세요")
                                .foregroundColor(.white)
                        }
                        // 드래그 이동 / 휠 확대축소
                        ZStack {  // ✅ ZStack을 사용해서 여러 개의 뷰를 포함
                            ScrollWheelView { delta in
                                print("🌀 scrollWheel delta=", delta)
                                let factor = 1 + (delta / 100)
                                previewScale = max(0.1, previewScale * factor)
                            }
                            .allowsHitTesting(false)
                            /*TrackpadGestureView { translation in
                                previewPosition.width += translation.width
                                previewPosition.height += translation.height
                            }*/
                            .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargetActive) { providers in
                        if let provider = providers.first {
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                                if let data = data as? Data,
                                   let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                                    DispatchQueue.main.async {
                                        // PNG 체크
                                        if url.pathExtension.lowercased() == "png" {
                                            selectedFile = url
                                            previewPosition = CGSize(width: 0, height: 0)
                                            // 변환 시작 (1초 지연)
                                            startConversionPreview()
                                        } else {
                                            errorMessage = "PNG 파일만 열 수 있습니다."
                                            showErrorAlert = true
                                        }
                                    }
                                }
                            }
                        }
                        return true
                    }
                    .onAppear {
                        previewPosition = CGSize(width: 0, height: 0)
                    }
                    .frame(width: 960, height: 450)
                    .clipped()
                    .cornerRadius(16)
                    .overlay(
                        // 🎯 확대/축소 컨트롤 버튼 (박스 안에 배치 + 가장 위로 올림)
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                // 🆕 보간 토글 버튼
                                /*
                                Button(action: {
                                    isInterpolationDisabled.toggle()
                                }) {
                                    //Image(systemName: isInterpolationDisabled ? "square.slash" : "square.fill")
                                        //.font(.system(size: 16))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(width: 30, height: 30)
                                 */
                                
                                //확대축소 버튼
                                Button(action: {
                                    previewScale = max(0.1, previewScale - 0.3) // 최소 배율 제한
                                }) {
                                    Image(systemName: "minus.magnifyingglass")
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(width: 30, height: 30)

                                Text("\(String(format: "%.1f", previewScale))x")
                                    .frame(width: 40)
                                    .font(.system(size: 14))
                                    .multilineTextAlignment(.center)

                                Button(action: {
                                    previewScale = min(5.0, previewScale + 0.3) // 최대 배율 제한
                                }) {
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(width: 30, height: 30)

                                Button(action: {
                                    previewScale = 1.0 // 배율 초기화
                                    previewPosition = .zero // 위치 초기화
                                    lastDragPosition = .zero // 마지막 위치 초기화
                                }) {
                                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle")
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(width: 30, height: 30)
                            }
                            .padding(6)
                            .background(Color.gray.opacity(0.5))
                            .cornerRadius(8)
                            .padding(12)
                            .zIndex(100) // 🎯 버튼을 최상단으로 배치
                        }
                        .allowsHitTesting(true) // 버튼이 터치 가능하도록 설정
                    )
                    
                    if let selectedFile = selectedFile {
                        Text("선택된 파일: \(selectedFile.lastPathComponent)")
                            .padding()
                            .frame(minWidth: 500)
                    }
                    if let outputFile = outputFile {
                        let fileSize = getFileSize(fileURL: outputFile)
                        if fileSize.isEmpty || fileSize == "N/A" {
                            Text("파일 크기를 가져올 수 없습니다. 슬라이더를 움직여서 다시 시도해 주세요.")
                                .foregroundColor(.red)
                                .padding()
                                .frame(minWidth: 500)
                        }
                    } else {
                        Text("파일을 추가해주세요.")
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    HStack {
                        Text("현재 용량: \(currentSize) KB")
                            .padding()
                        Spacer()
                        if let outputFile = outputFile {
                            let fileSize = getFileSize(fileURL: outputFile)
                            Text("변환 후 용량: \(fileSize) KB (\(String(format: "%.1f", (Double(fileSize) ?? 0) / (Double(currentSize) ?? 1) * 100))%)")
                                .padding()
                        }
                    }
                    
                    GroupBox() {
                        // 품질 슬라이더 + 입력
                        HStack() {
                            Text("압축 품질")
                            Spacer()
                            Slider(value: $quality, in: 10...90, step: 10) { editing in
                                if !editing, selectedFile != nil {
                                    startConversionPreview()
                                }
                            }
                            .frame(width: 680)
                            .multilineTextAlignment(.trailing)
                            
                            TextField("10~90", value: $quality, formatter: qualityFormatter)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if selectedFile != nil {
                                        startConversionPreview()
                                }
                            }
                        }
                        .padding(8)
                        
                        // 색상 수 슬라이더 + 입력
                        HStack {
                            Text("색상 수")
                            Spacer()
                            Slider(value: $colorCount, in: 48...256, step: 16) { editing in
                                if !editing, selectedFile != nil {
                                    startConversionPreview()
                                }
                            }
                            .frame(width: 680)
                            .multilineTextAlignment(.trailing)
                            
                            TextField("48~256", value: $colorCount, formatter: colorCountFormatter)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if selectedFile != nil {
                                        startConversionPreview()
                                }
                            }
                        }
                        .padding(8)
                        
                        // 디더링
                        HStack {
                            Text("Floyd–Steinberg 디더링")
                            Spacer()
                            Slider(value: $floyd, in: 0...1, step: 0.1) { editing in
                                if !editing, selectedFile != nil {
                                    startConversionPreview()
                                }
                            }
                            .frame(width: 680)
                            .multilineTextAlignment(.trailing)
                            
                            TextField("0~1", value: $floyd, formatter: floydFormatter)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if selectedFile != nil {
                                        startConversionPreview()
                                }
                            }
                        }
                        .padding(8)
                        
                        // 속도
                        HStack {
                            Text("S/Q")
                            Spacer()
                            Slider(value: $speed, in: 1...11, step: 1) { editing in
                                if !editing, selectedFile != nil {
                                    startConversionPreview()
                                }
                            }
                            .frame(width: 680)
                            .multilineTextAlignment(.trailing)
                            
                            TextField("1~11", value: $speed, formatter: speedFormatter)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if selectedFile != nil {
                                        startConversionPreview()
                                }
                            }
                        }
                        .padding(8)
                    }
                    
                    // 저장 버튼
                    if let originalURL = selectedFile, let tempURL = outputFile {
                        VStack(alignment: .trailing) {
                            Divider()
                                .padding(.top)
                            HStack {
                                Button("새로고침") {
                                    isConverting = false
                                    previewImage = nil
                                    selectedFile = nil
                                    outputFile = nil
                                    deleteTemporaryFiles()
                                }
                                Button("저장") {
                                    isConverting = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        saveOverOriginal(originalURL: originalURL, tempURL: tempURL)
                                        isConverting = false
                                    }
                                }
                            }
                            .padding(.top)
                        }
                    }
                }
                .padding()
                .alert("저장 완료", isPresented: $showingSaveAlert) {
                    Button("확인", role: .cancel) {}
                }
                .alert("오류", isPresented: $showErrorAlert) {
                    Button("확인", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
                .disabled(isConverting)
                .overlay(
                    Group {
                        if isConverting {
                            Color.black.opacity(0.2).ignoresSafeArea()
                            Text("변환 중…")
                                .padding(30)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(radius: 4)
                                .foregroundColor(.black)
                        }
                    }
                )
                
            } else {
                // 설정 탭
                VStack {
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text("오픈소스 라이선스")
                                .font(.title)
                                .bold()
                                .padding(.bottom)
                            
                            Text("이 앱은 pngquant을 사용합니다.")
                                .font(.headline)
                            
                            Text("""
                                pngquant © 2009-2018 by Kornel Lesiński.
                                GNU General Public License v3 (GPL v3) 또는 그 이후 버전으로 배포됩니다.
                                
                                소스 코드 및 라이선스 내용은 다음을 참조하세요:
                                https://github.com/kornelski/pngquant
                                
                                BSD 라이선스 적용 파일:
                                - `rwpng.c/h` 및 일부 코드
                                
                                --
                                GPL v3 공개의무에 따른 소스코드 공개
                                https://github.com/nazonoz/pngquant_gui_for_macOS
                                --
                                
                                옵션 설명
                                압축품질 : 전체적인 품질 적용.
                                색상 수 : 압축에 사용할 색상 수. 색상을 적게 사용할 수록 용량이 줄어듬.
                                Floyd–Steinberg 디더링 : Floyd–Steinberg 알고리즘 기반 디더링 적용 강도. 0 = 적용안함, 1 = 최대치 적용.
                                S/Q : Speed/Quality Trade-off. 1=로딩속도가 느리고 품질이 좋음, 11=로딩속도가 빠르고 품질이 나쁨. 로딩속도가 용량을 뜻하지는 않음
                                
                                --
                                
                                v0.1.4
                                자동 업데이트 기능 추가
                                
                                v0.1.3
                                최초공개버전
                                """)
                            .font(.body)
                            .padding(.top, 5)
                        }
                        .padding()
                    }
                    HStack {
                        Button("업데이트 확인") {
                            updateManager.checkForUpdates()
                        }
                        .padding()
                        Button("임시 파일 폴더 보기") {
                            showTemporaryFolder()
                        }
                        .padding()
                        Button("임시 파일 일괄 삭제") {
                            deleteTemporaryFiles()
                        }
                        .padding()
                    }
                }
                .padding()
            }
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isSettingsTabActive.toggle()
                }) {
                    Label(isSettingsTabActive ? "변환" : "설정", systemImage: isSettingsTabActive ? "photo.badge.magnifyingglass" : "person.fill.questionmark")
                }
            }
        }.navigationTitle("난 누군가 또 여긴 어딘가")
    }
    
    // 변환(1초 대기)
    private func startConversionPreview() {
        guard let file = selectedFile else { return }
        isConverting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            previewCompressedImage(file, quality: Int(quality), colorCount: Int(colorCount), floyd: floyd, speed: Int(speed))
            isConverting = false
        }
    }
    
    // 디버그 로그를 추가한 변환 함수
    private func previewCompressedImage(_ inputPath: URL, quality: Int, colorCount: Int, floyd: Double, speed: Int) {
        print("➡️ previewCompressedImage() start with file=\(inputPath.path), quality=\(quality), colorCount=\(colorCount), floyd=\(floyd), speed=\(speed)")
            
        let tmpDirectory = FileManager.default.temporaryDirectory
        let previewPath = tmpDirectory.appendingPathComponent(
            inputPath.deletingPathExtension().lastPathComponent + "_preview.png"
        )
        previewFile = previewPath
        
        // 기존 파일 삭제
        if let previewFile = previewFile, FileManager.default.fileExists(atPath: previewFile.path) {
            do {
                print("🗑 기존 미리보기 파일 삭제: \(previewFile.path)")
                try FileManager.default.removeItem(at: previewFile)
            } catch {
                print("❌ 미리보기 파일 삭제 오류: \(error.localizedDescription)")
            }
        }
        
        // pngquant 실행
        guard let pngquantPath = Bundle.main.path(forResource: "pngquant", ofType: "") else {
            print("❌ pngquant 실행 파일을 찾을 수 없습니다.")
            return
        }
        print("✅ pngquantPath: \(pngquantPath)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pngquantPath)
        process.arguments = [
            "--quality=\(quality)-\(quality+5)",
            "--colors=\(colorCount)",
            "--floyd=\(floyd)",
            "--speed=\(speed)",
            "--output", previewPath.path,
            inputPath.path
        ]
        
        do {
            print("▶️ pngquant 실행 준비… arguments=\(process.arguments ?? [])")
            try process.run()
            print("▶️ pngquant 실행 중…")
            process.waitUntilExit()
            print("✅ pngquant 변환 완료. 결과 파일 경로: \(previewPath.path)")
            
            if FileManager.default.fileExists(atPath: previewPath.path) {
                print("✅ 변환된 파일 존재: \(previewPath.path)")
                if let image = NSImage(contentsOf: previewPath) {
                    DispatchQueue.main.async {
                        print("✅ 미리보기 이미지 로드 성공.")
                        self.previewImage = image
                        self.outputFile = previewPath
                        self.previewScale = 1.0
                        self.previewPosition = CGSize(width: 0, height: 0)
                        self.currentSize = getFileSize(fileURL: inputPath)
                    }
                } else {
                    print("❌ NSImage 로드 실패. 변환된 파일이 손상되었거나 0바이트일 수 있음.")
                }
            } else {
                print("❌ 변환 결과 파일이 생성되지 않음: \(previewPath.path)")
            }
            
        } catch {
            print("❌ pngquant 호출 오류: \(error.localizedDescription)")
        }
    }
    
    // 파일 용량(KB)
    private func getFileSize(fileURL: URL) -> String {
        let fm = FileManager.default
        do {
            let attrs = try fm.attributesOfItem(atPath: fileURL.path)
            if let size = attrs[.size] as? NSNumber {
                return String(format: "%.2f", size.doubleValue / 1024.0)
            }
        } catch {
            print("파일 크기 계산 오류: \(error.localizedDescription)")
        }
        return "N/A"
    }
    
    // 저장(임시파일 -> 원본)
    private func saveOverOriginal(originalURL: URL, tempURL: URL) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: originalURL)
            try fm.copyItem(at: tempURL, to: originalURL)
            previewImage = nil
            selectedFile = nil
            outputFile = nil
            deleteTemporaryFiles()
            print("💾 저장 완료. 원본에 임시파일을 덮어씌움.")
            showingSaveAlert = true
        } catch {
            print("저장 오류: \(error.localizedDescription)")
        }
    }
    
    // 임시 폴더 열기
    private func showTemporaryFolder() {
        let tmpDirectory = FileManager.default.temporaryDirectory
        NSWorkspace.shared.open(tmpDirectory)
    }
    
    // 임시 파일 삭제
    private func deleteTemporaryFiles() {
        let tmpDirectory = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tmpDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            print("임시 파일 삭제 완료")
        } catch {
            print("임시 파일 삭제 오류: \(error.localizedDescription)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
