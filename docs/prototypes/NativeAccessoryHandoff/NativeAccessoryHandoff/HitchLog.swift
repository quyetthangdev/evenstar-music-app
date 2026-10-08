//  SPIKE — `-hitchLog <path>`: ghi mỗi khung main thread trễ > 20 ms
//  (CADisplayLink) cùng các mốc sự kiện, để biết cú khựng lúc thả tay là
//  do app (main thread bận) hay do render server.

import UIKit
import QuartzCore

final class HitchLog: NSObject {
    static let shared = HitchLog()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var handle: FileHandle?
    private let t0 = CACurrentMediaTime()

    func start() {
        guard let path = Args.value("-hitchLog"), link == nil else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    func mark(_ what: @autoclosure () -> String) {
        guard handle != nil else { return }
        write(String(format: "%8.3f  MARK %@\n", CACurrentMediaTime() - t0, what()))
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        if last > 0, now - last > 0.020 {
            write(String(format: "%8.3f  HITCH %.0f ms\n", now - t0, (now - last) * 1000))
        }
        last = now
    }

    private func write(_ s: String) {
        handle?.write(s.data(using: .utf8)!)
    }
}
