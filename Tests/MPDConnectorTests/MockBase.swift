//
//  MockBase.swift
//  MPDConnector
//
// The MIT License (MIT)
//
// Copyright (c) 2018 Katoemba Software
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import XCTest
import Foundation

class MockBase {
    /// Dictionary of calls (functionName as key) and parameters as value.
    /// Values is an array of dictionaries, where key=parameter-name, value=parameter-value
    private var calls = [String: [[String: String]]]()
    private let semaphore = DispatchSemaphore(value: 1)
    
    /// Register that a call was made.
    ///
    /// - Parameters:
    ///   - functionName: Name of the function that was called.
    ///   - parameters: Dictionary of parameters that were passed to the function.
    func registerCall(_ functionName: String, _ parameters: [String: String]) {
        semaphore.wait()
        if var callInfos = calls[functionName] {
            callInfos.append(parameters)
            calls[functionName] = callInfos
        }
        else {
            calls[functionName] = [parameters]
        }
        semaphore.signal()
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
