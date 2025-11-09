//
//  main.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation



let VERSION = 0.8

print(WELCOME_MSG)
print("Version: \(VERSION)")

extension String{
    func startswith(_ string: String) -> Bool{
        return self.hasPrefix(string)
    }
    
    
    func format(arguments: [CVarArg]) -> String{
        let string = String(format: self, arguments: arguments)
        return string
    }
}

extension [String]{
    func contains(_ string: String) -> Bool{
        return self.contains { str in
            str == string
        }
    }
    func contains(_ cliArg: CommandLineArgs) -> Bool{
        return self.contains(cliArg.rawValue)
    }
    func findArgumentValue(_ cliArgs: CommandLineArgs) throws -> String{
        if let index = self.firstIndex(of: cliArgs.rawValue){
            if (index + 1) < self.count{
                return self[index + 1]
            }else{
                print("Unable to find a value for: \(cliArgs.rawValue)")
                throw CLIExceptions.MissingArguments
            }
        }else{
            print("Unable to find index for: \(cliArgs.rawValue)")
            throw CLIExceptions.MissingArguments
        }
        
        
    }
    func findArgumentValues(_ cliArgs: CommandLineArgs) -> [String]{
        if let index = self.firstIndex(of: cliArgs.rawValue){
            if (index + 1) < self.count{
                return [String](self.suffix(from: index + 1))
            }
        }
        
        return []
    }
}



var PASSWORD: String = "NONE"
let arguments = CommandLine.arguments
let PW_location = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".sdist")

// Initialize Secure Enclave commands on macOS
#if os(macOS)
addSecureEnclaveCommands()
#endif

func user_interface() throws{
    while true{
        let cmds = COMMANDS.sorted(by: {
            let l1 = $0.key.count + ($0.value["description"] as! String).count
            let l2 = $1.key.count + ($1.value["description"] as! String).count
            
            return l1 < l2
        })

        print("Commands:")
        for command in cmds {
            print("\t\(command.key): \(command.value["description"]!)")
        }
        
        print("Ener a command: ", terminator: "")
        let cmd = readLine()!
        
        if cmd == "exit"{
            exit(EXIT_SUCCESS)
        }
        
        if let command = COMMANDS[cmd]{
            guard let function = command["function"]! as? (dynamicParams) throws -> Void else {
                throw CLIExceptions.UnableToCastFunction
            }
            
            let showOperation = String(repeating: "*", count: Int(Double(getTerminalColumns() ?? 100) * 0.5))
            print(showOperation)
            try function(.init())
            print(showOperation)
        }
    }
}

func commandLineMode() throws{
    let function = try arguments.findArgumentValue(.functionArg)
    let args = arguments.findArgumentValues(.argumentsArg)
    
    print("Function: \(function)")
    print("Args: \(args)")
    
    if let cmd = COMMANDS[function]{
        guard let function = cmd["function"]! as? (dynamicParams) throws -> Void else { throw CLIExceptions.UnableToCastFunction }
        if args.count > 0{
            try function(.init(fromArray: args))
        }else{
            try function(.init())
        }
    }
}



do{
    // check if the help message arg was passed
    if arguments.contains(.helpArg){
        print("Generating docs...")
        let docs = generateDocs()
        print(docs)
        
        exit(EXIT_SUCCESS)
    }
    
    
    if arguments.contains(.commandLineMode){
        PASSWORD = try arguments.findArgumentValue(.passwordArg)
        try commandLineMode()
    }else{
        if let pw = try? load_password(){
            PASSWORD = pw
        }else{
            PASSWORD = askUser(question: "Enter Password:")
        }
        try user_interface()
    }
    
} catch {
    print("Error: \(error)")
    exit(EXIT_FAILURE)
}



