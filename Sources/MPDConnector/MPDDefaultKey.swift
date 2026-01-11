//
//  DefaultsKey.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 26/12/2025.
//

internal enum MPDDefaultKey: String {
    case coverHttpPort = "MPD.Uri.Port"
    case coverPrefix = "MPD.Uri.Prefix"
    case coverPostfix = "MPD.Uri.Postfix"
    case alternativeCoverPostfix = "MPD.Uri.AlternativePostfix"
    case alternativeCoverHost = "MPD.Uri.AlternativeCoverHost"
    case binaryCoverArt = "BinaryCoverArt"
    case embeddedCoverArt = "EmbeddedCoverArt"
    case urlCoverArt = "URLCoverArt"
    case discogsCoverArt = "DiscogsCoverArt"
    case musicbrainzCoverArt = "MusicbrainzCoverArt"
    case version = "MPD.Version"
    case MPDType = "type"
    case outputHost = "MPD.Output.Host"
    case outputPort = "MPD.Output.Port"
    case ipAddress = "MPD.IpAddress"
    case connectToIpAddress = "MPD.ConnectToIpAddress"
    case customPlayerName = "MPD.CustomPlayerName"
    case hidden = "MPD.Hidden"
    
    func stringValue(_ player: MPDPlayer) -> String {
        return player.defaultsKey(self.rawValue)
    }
    
    func stringValue(_ uniqueID: String) -> String {
        return self.rawValue + "." + uniqueID
    }
}
