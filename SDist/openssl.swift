import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func openssl_encrypt(_ inputFile: String, outputFile: String) {
    let cleanInputFile = inputFile.trimmingCharacters(in: .whitespaces)
    let cleanOutputFile = outputFile.trimmingCharacters(in: .whitespaces)
    
    let args = [
        "openssl",
        "enc",
        "-aes-256-cbc",
        "-salt",
        "-pbkdf2",
        "-iter",
        "1000000",
        "-in",
        cleanInputFile,
        "-out",
        cleanOutputFile
    ]
    print("OpenSSL Args:", args)
    var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    cArgs.append(nil)
    
    var pid: pid_t = 0
    let status = posix_spawn(&pid, "/usr/bin/openssl", nil, nil, &cArgs, environ)
    
    // Free C strings
    for arg in cArgs where arg != nil {
        free(arg)
    }
    
    if status == 0 {
        // Wait for child process to finish
        var waitStatus: Int32 = 0
        waitpid(pid, &waitStatus, 0)
        
        let exitCode = (waitStatus >> 8) & 0xFF
        if exitCode != 0 {
            print("OpenSSL failed with exit code: \(exitCode)")
        }
    } else {
        print("Failed to spawn process: \(String(cString: strerror(status)))")
    }
}

func openssl_decrypt(_ inputFile: String, outputFile: String) {
    let cleanInputFile = inputFile.trimmingCharacters(in: .whitespaces)
    let cleanOutputFile = outputFile.trimmingCharacters(in: .whitespaces)
    
    let args = [
        "openssl",
        "enc",
        "-d",
        "-aes-256-cbc",
        "-salt",
        "-pbkdf2",
        "-iter",
        "1000000",
        "-in",
        cleanInputFile,
        "-out",
        cleanOutputFile
    ]
    print("OpenSSL Args:", args)
    var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    cArgs.append(nil)
    
    var pid: pid_t = 0
    let status = posix_spawn(&pid, "/usr/bin/openssl", nil, nil, &cArgs, environ)
    
    for arg in cArgs where arg != nil {
        free(arg)
    }
    
    if status == 0 {
        var waitStatus: Int32 = 0
        waitpid(pid, &waitStatus, 0)
        
        let exitCode = (waitStatus >> 8) & 0xFF
        if exitCode != 0 {
            print("OpenSSL failed with exit code: \(exitCode)")
        }
    } else {
        print("Failed to spawn process: \(String(cString: strerror(status)))")
    }
}
