//
//  HTTP2FrameWriter.swift
//  PerfectHTTPServer
//
//  Created by Kyle Jessup on 2017-06-21.
//
//

import PerfectNet
import PerfectThread
import Dispatch

class HTTP2FrameWriter {
	private let net: NetTCP
	private var enqueuedFrames = [HTTP2Frame]()
	private let enqueuedFramesLock = Threading.Event()
	private let writeFramesThread = DispatchQueue(label: "HTTP2FrameWriter")
	var windowSize = Int.max
	init(_ net: NetTCP) {
		self.net = net
		startFrameWriting()
	}
	
	func waitUntilEmpty(_ callback: () -> ()) {
		while true {
			enqueuedFramesLock.lock()
			if enqueuedFrames.isEmpty {
				callback()
			} else {
				_ = enqueuedFramesLock.wait()
			}
			enqueuedFramesLock.unlock()
		}
	}
	
	func enqueueFrame(_ frame: HTTP2Frame) {
		enqueuedFramesLock.lock()
		enqueuedFrames.append(frame)
		enqueuedFramesLock.signal()
		enqueuedFramesLock.unlock()
	}
	
	private func startFrameWriting() {
		guard net.isValid else {
			return
		}
		writeFramesThread.async {
			self.enqueuedFramesLock.lock()
			if self.enqueuedFrames.isEmpty {
				_ = self.enqueuedFramesLock.wait(seconds: 0.5)
			}
			guard let frame = self.enqueuedFrames.first else {
				self.enqueuedFramesLock.unlock()
				return self.startFrameWriting()
			}
			self.enqueuedFrames.remove(at: 0)
			self.enqueuedFramesLock.unlock()
			let bytes = frame.headerBytes() + (frame.payload ?? [])
			self.net.write(bytes: bytes) {
				wrote in
				self.startFrameWriting()
			}
		}
	}
}
