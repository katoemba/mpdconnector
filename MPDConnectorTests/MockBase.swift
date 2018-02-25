//
//  MockBase.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 10-08-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
//

import XCTest
import Foundation

class MockBase {
    /// Dictionary of calls (functionName as key) and parameters as value.
    /// Values is an array of dictionaries, where key=parameter-name, value=parameter-value
    private var calls = [String: [[String: String]]]()
    
    /// Register that a call was made.
    ///
    /// - Parameters:
    ///   - functionName: Name of the function that was called.
    ///   - parameters: Dictionary of parameters that were passed to the function.
    func registerCall(_ functionName: String, _ parameters: [String: String]) {
        if var callInfos = calls[functionName] {
            callInfos.append(parameters)
            calls[functionName] = callInfos
        }
        else {
            calls[functionName] = [parameters]
        }
    }
    
    func clearAllCalls() {
        calls = [String: [[String: String]]]()
    }
    
    func callCount(_ functionName: String) -> Int {
        guard let callInfos = calls[functionName] else {
            return 0
        }

        return callInfos.count
    }
    
    func assertCall(_ functionName: String, expectedCallCount: Int = 1, expectedParameters: [String: String] = [:]) {
        var callCount = 0
        if let callInfos = calls[functionName] {
            if expectedParameters == [:] {
                callCount = callInfos.count
            }
            else {
                for callInfo in callInfos {
                    var allIsGood = true
                    for expectedParameter in expectedParameters.keys {
                        let expectedValue = expectedParameters[expectedParameter]
                        let actualValue = callInfo[expectedParameter]
                        
                        if expectedValue != actualValue && expectedValue != "*" {
                            allIsGood = false
                            break
                        }
                    }
                    
                    if allIsGood {
                        callCount = callCount + 1
                    }
                }
            }
        }
        XCTAssert(callCount == expectedCallCount, "Expected \(expectedCallCount) calls to '\(functionName)', actual number of calls is \(callCount)")
    }    

    func assertCall(_ functionName: String, callInstance: Int, expectedParameters: [String: String] = [:]) {
        if let callInfos = calls[functionName], callInstance < callInfos.count {
            let callInfo = callInfos[callInstance]

            for expectedParameter in expectedParameters.keys {
                let expectedValue = expectedParameters[expectedParameter]
                let actualValue = callInfo[expectedParameter]
                
                if actualValue != nil {
                    XCTAssert(expectedValue == actualValue, "\(functionName): expected \(expectedValue!) for parameter \(expectedParameter), got \(actualValue!)")
                }
                else {
                    XCTAssert(false, "\(functionName): no value found for parameter \(expectedParameter)")
                }
            }
            
        }
        else {
            XCTAssert(false, "Call(\(callInstance) to '\(functionName)' not found")
        }
    }
}
