//
//  MPDHelper.swift
//  MPDConnector_iOS
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

import Foundation
import RxSwift
import ConnectorProtocol
import RxSwiftExt

public class MPDHelper {
    private enum ConnectError: Error {
        case error
        case permission
    }
    
    public static func hostToUse(_ connectionProperties: [String: Any]) -> String {
        var host = connectionProperties[ConnectionProperties.host.rawValue] as! String
        if (connectionProperties[MPDConnectionProperties.connectToIpAddress.rawValue] as? Bool) == true,
           let ipAddress = connectionProperties[MPDConnectionProperties.ipAddress.rawValue] as? String {
            host = ipAddress
        }
        return host
    }
    
    /// Compare two mpd version strings
    ///
    /// - Parameters:
    ///   - leftVersion: the left version string to compare
    ///   - rightVersion: the right version string to compare
    /// - Returns: The ordering of the two versions
    public static func compareVersion(leftVersion: String, rightVersion: String) -> ComparisonResult {
        let leftComponents = leftVersion.split(separator: ".")
        let rightComponents = rightVersion.split(separator: ".")
        let numberOfComponents = min(leftComponents.count, rightComponents.count)
        
        for x in 0..<numberOfComponents {
            let leftValue = Int(leftComponents[x]) ?? 0
            let rightValue = Int(rightComponents[x]) ?? 0
            
            if leftValue < rightValue {
                return .orderedAscending
            }
            else if leftValue > rightValue {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
    
    private static let volumeAdjustmentKey = "MPDControl.volumeAdjustmentKey"
    public static func playerVolumeAdjustmentKey(_ playerName: String) -> String {
        volumeAdjustmentKey + "." + playerName
    }

    public static func adjustedVolumeToPlayer(_ volume: Float, volumeAdjustment: Float?) -> Float {
        guard let volumeAdjustment = volumeAdjustment else { return volume }
        if volume < 0.5 {
            return volume * volumeAdjustment * 2
        }
        else if volume > 0.5 {
            return volumeAdjustment + ((volume - 0.5) * (1 - volumeAdjustment) * 2)
        }
        
        return volumeAdjustment
    }

    public static func adjustedVolumeFromPlayer(_ volume: Float, volumeAdjustment: Float?) -> Float {
        guard let volumeAdjustment = volumeAdjustment else { return volume }
        
        if volume < volumeAdjustment {
            return (volume / volumeAdjustment) / 2.0
        }
        else if volume > volumeAdjustment {
            return 0.5 + ((volume - volumeAdjustment) * 0.5 ) / (1 - volumeAdjustment)
        }
        
        return volume
    }
}
