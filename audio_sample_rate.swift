#!/usr/bin/swift

import Foundation
import CoreAudio

// MARK: - Core Audio Helper Functions

func getDefaultOutputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &deviceIDSize,
        &deviceID
    )
    
    if status == noErr {
        return deviceID
    }
    return nil
}

func getDeviceName(deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    // First, get the size of the property
    var nameSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &nameSize
    )
    
    guard status == noErr else { return nil }
    
    // Create a buffer to hold the CFString reference
    let buffer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
    defer { buffer.deallocate() }
    
    status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &nameSize,
        buffer
    )
    
    if status == noErr, let name = buffer.pointee {
        return name as String
    }
    return nil
}

func getAvailableSampleRates(deviceID: AudioDeviceID) -> [Double] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &dataSize
    )
    
    guard status == noErr else { return [] }
    
    let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
    var ranges = [AudioValueRange](repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
    
    status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &ranges
    )
    
    guard status == noErr else { return [] }
    
    var sampleRates = Set<Double>()
    for range in ranges {
        sampleRates.insert(range.mMinimum)
        if range.mMaximum != range.mMinimum {
            sampleRates.insert(range.mMaximum)
        }
    }
    
    return Array(sampleRates).sorted()
}

func getCurrentSampleRate(deviceID: AudioDeviceID) -> Double? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var sampleRate: Float64 = 0
    var dataSize = UInt32(MemoryLayout<Float64>.size)
    
    let status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &sampleRate
    )
    
    if status == noErr {
        return sampleRate
    }
    return nil
}

func setSampleRate(deviceID: AudioDeviceID, sampleRate: Double) -> Bool {
    // Try both global and output scopes
    let scopes = [kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyScopeOutput]
    
    for scope in scopes {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Check if the property is settable
        var isSettable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(
            deviceID,
            &address,
            &isSettable
        )
        
        if settableStatus == noErr && isSettable.boolValue {
            var rate = sampleRate
            let dataSize = UInt32(MemoryLayout<Float64>.size)
            
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                dataSize,
                &rate
            )
            
            if status == noErr {
                // Wait a bit for the change to take effect
                usleep(100000) // 100ms
                return true
            } else if status == kAudioDeviceUnsupportedFormatError {
                print("Note: Device reports format unsupported for scope \(scope == kAudioObjectPropertyScopeGlobal ? "global" : "output")")
            } else if status == kAudioHardwareBadObjectError {
                print("Note: Bad object error for scope \(scope == kAudioObjectPropertyScopeGlobal ? "global" : "output")")
            }
        }
    }
    
    return false
}

// MARK: - Main Program

func printUsage() {
    print("""
    Usage: audio-sample-rate [OPTIONS]
    
    Options:
      -l, --list              List available sample rates for current device
      -c, --current           Show current sample rate
      -s, --set <rate>        Set sample rate (e.g., 44100, 48000, 96000)
      -h, --help              Show this help message
    
    Examples:
      audio-sample-rate --list
      audio-sample-rate --current
      audio-sample-rate --set 48000
    """)
}

// Parse arguments
let args = CommandLine.arguments
if args.count < 2 {
    printUsage()
    exit(1)
}

guard let deviceID = getDefaultOutputDevice() else {
    print("Error: Could not get default output device")
    exit(1)
}

let deviceName = getDeviceName(deviceID: deviceID) ?? "Unknown Device"

switch args[1] {
case "-l", "--list":
    print("Device: \(deviceName)")
    print("\nAvailable sample rates:")
    let rates = getAvailableSampleRates(deviceID: deviceID)
    if rates.isEmpty {
        print("  No sample rates available (device may not support rate changes)")
    } else {
        for rate in rates {
            let current = getCurrentSampleRate(deviceID: deviceID)
            let marker = (current == rate) ? " (current)" : ""
            print("  \(Int(rate)) Hz\(marker)")
        }
    }
    
case "-c", "--current":
    if let currentRate = getCurrentSampleRate(deviceID: deviceID) {
        print("Device: \(deviceName)")
        print("Current sample rate: \(Int(currentRate)) Hz")
    } else {
        print("Error: Could not get current sample rate")
        exit(1)
    }
    
case "-s", "--set":
    guard args.count >= 3 else {
        print("Error: Sample rate not specified")
        printUsage()
        exit(1)
    }
    
    guard let targetRate = Double(args[2]) else {
        print("Error: Invalid sample rate '\(args[2])'")
        exit(1)
    }
    
    // Check if rate is available
    let availableRates = getAvailableSampleRates(deviceID: deviceID)
    if !availableRates.isEmpty && !availableRates.contains(targetRate) {
        print("Error: Sample rate \(Int(targetRate)) Hz is not supported by this device")
        print("\nAvailable rates:")
        for rate in availableRates {
            print("  \(Int(rate)) Hz")
        }
        exit(1)
    }
    
    // Show current rate before change
    let originalRate = getCurrentSampleRate(deviceID: deviceID)
    print("Device: \(deviceName)")
    if let rate = originalRate {
        print("Current sample rate: \(Int(rate)) Hz")
    }
    print("Attempting to set sample rate to \(Int(targetRate)) Hz...")
    
    if setSampleRate(deviceID: deviceID, sampleRate: targetRate) {
        // Wait a bit more for the change to propagate
        usleep(500000) // 500ms
        
        // Verify the change
        if let newRate = getCurrentSampleRate(deviceID: deviceID) {
            if abs(newRate - targetRate) < 1.0 {
                print("✓ Sample rate changed successfully to \(Int(newRate)) Hz")
            } else {
                print("⚠️ Sample rate change was accepted but device is still at \(Int(newRate)) Hz")
                print("  The device may require exclusive access or may be in use by another application.")
                print("  Try closing other audio applications (DAWs, browsers, music players, etc.) and retry.")
            }
        } else {
            print("⚠️ Could not verify the new sample rate")
        }
    } else {
        print("✗ Failed to change sample rate")
        print("Possible reasons:")
        print("  - The device may not support sample rate changes")
        print("  - The audio device may be in use by another application")
        print("  - You may need to run with elevated permissions")
        print("  - Try closing audio applications and retry")
        exit(1)
    }
    
case "-h", "--help":
    printUsage()
    
default:
    print("Error: Unknown option '\(args[1])'")
    printUsage()
    exit(1)
}
