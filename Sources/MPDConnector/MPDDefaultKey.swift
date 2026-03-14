//
//  DefaultsKey.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 26/12/2025.
//

public enum MPDDefaultKey: String {
    case coverHttpPort = "MPD.Uri.Port"
    case coverPrefix = "MPD.Uri.Prefix"
    case coverPostfix = "MPD.Uri.Postfix"
    case alternativeCoverPostfix = "MPD.Uri.AlternativePostfix"
    case alternativeCoverHost = "MPD.Uri.AlternativeCoverHost"
    case version = "MPD.Version"
    case MPDType = "type"
    case outputHost = "MPD.Output.Host"
    case outputPort = "MPD.Output.Port"
    case ipAddress = "MPD.IpAddress"
    case connectToIpAddress = "MPD.ConnectToIpAddress"
    case customPlayerName = "MPD.CustomPlayerName"
    case hidden = "MPD.Hidden"
    case password = "MPD.Password"
    case useHttpCoverArt = "MPD.UseHttpCoverArt"
    case manualPlayers = "MPD.ManualPlayers"
    case albumGrouping = "MPD.AlbumGrouping"
    
    public func stringValue(_ player: MPDPlayer) -> String {
        return player.defaultsKey(self.rawValue)
    }
    
    public func stringValue(_ uniqueID: String) -> String {
        return self.rawValue + "." + uniqueID
    }
    
    public func stringValue(host: String, port: Int) -> String {
        return self.rawValue + "." + MPDPlayer.uniqueIDForPlayer(host: host, port: port)
    }
}
