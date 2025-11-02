//
//  subprocesses.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation

func GET(url: String) -> String? {
    let task = Process()
    let pipe = Pipe()
    
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["curl", "-L", url]
    task.standardOutput = pipe
    
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        return output
    } catch {
        print("Error executing command: \(error)")
        return nil
    }
}

func downloadFile(url: String, saveName: String) {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["curl", "--progress-bar", "-L", "-o", saveName, url]
    task.launch()
    task.waitUntilExit()
}

func unzip(tempFilePath: String){
    let task = Process()
    task.launchPath = "/usr/bin/unzip"
    task.arguments = [tempFilePath]
    let devNull = FileHandle.nullDevice
    task.standardOutput = devNull
    task.standardError = devNull

    task.launch()
    task.waitUntilExit()
}

func mv(_ string: String, destination: String){
    let task1 = Process()
    task1.launchPath = "/bin/mv"
    task1.arguments = [string, destination]
    task1.launch()
    task1.waitUntilExit()
}

func rm(_ string: String){
    let task2 = Process()
    task2.launchPath = "/bin/rm"
    task2.arguments = ["-rf", string]
}

func getTerminalColumns() -> Int? {
    let task = Process()
    task.launchPath = "/usr/bin/tput"
    task.arguments = ["cols"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    if let output = String(data: data, encoding: .utf8),
       let columns = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return columns
    }

    return nil
}
