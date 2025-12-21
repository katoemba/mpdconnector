//
//  OpenHomeSettingsView.swift
//
//
//  Created by GitHub Copilot on 25/10/2025.
//

import SwiftUI
import TipKit
import ConnectorProtocol

public struct MPDSettingsView: View {
    @ObservedObject private var player: MPDPlayer
    @State private var customPlayerName: String = ""
    @State private var selectedType: MPDType = MPDType.allCases.first!

    // New state for advanced and output settings
    @State private var ipAddressField: String = ""
    @State private var connectToIp: Bool = false
    @State private var outputHostField: String = ""
    @State private var outputPortField: String = ""

    // Database status
    @State private var databaseStatusText: String = ""
    @State private var databaseArtists: String = "-"
    @State private var databaseAlbums: String = "-"
    @State private var databaseSongs: String = "-"
    @State private var performingDBAction: Bool = false
    
    private let changeNameTip = MPDChangeNameTip()

    public init(player: MPDPlayer) {
        self.player = player
        
        // Initialize fields from userDefaults if available
        let uid = player.uniqueID
        let ud = player.userDefaults
        self._ipAddressField = State(initialValue: ud.string(forKey: MPDConnectionProperties.ipAddress.rawValue + "." + uid) ?? player.connectionProperties[MPDConnectionProperties.ipAddress.rawValue] as? String ?? "")
        self._connectToIp = State(initialValue: ud.bool(forKey: MPDConnectionProperties.connectToIpAddress.rawValue + "." + uid))
        self._outputHostField = State(initialValue: ud.string(forKey: MPDConnectionProperties.outputHost.rawValue + "." + uid) ?? (player.connectionProperties[MPDConnectionProperties.outputHost.rawValue] as? String ?? ""))
        if let portVal = ud.object(forKey: MPDConnectionProperties.outputPort.rawValue + "." + uid) as? Int {
            self._outputPortField = State(initialValue: "\(portVal)")
        } else if let portFromProps = player.connectionProperties[MPDConnectionProperties.outputPort.rawValue] as? String {
            self._outputPortField = State(initialValue: portFromProps)
        } else {
            self._outputPortField = State(initialValue: "")
        }
        self._customPlayerName = State(initialValue: ud.string(forKey: MPDConnectionProperties.customPlayerName.rawValue + "." + uid) ?? "")
        
        // Initialize selected type from player
        self._selectedType = State(initialValue: player.type)
    }

    public var body: some View {
        Form {
            // Player Information Section
            Section(header: Text("Player Information", bundle: .module)) {
                #if os(macOS)
                HStack {
                    Text("Type", bundle: .module)
                    Spacer()
                    Picker("Type", selection: $selectedType) {
                        ForEach(MPDType.selectableTypes, id: \.self) { t in
                            Text(String(describing: t)).tag(t)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedType) { _, newValue in
                        // Update player when type changes
                        player.type = newValue
                        let key = MPDConnectionProperties.MPDType.rawValue + "." + player.uniqueID
                        player.userDefaults.set(newValue.rawValue, forKey: key)
                        player.objectWillChange.send()
                    }
                }
                #else
                NavigationLink {
                    List {
                        ForEach(MPDType.selectableTypes, id: \.self) { t in
                            HStack {
                                Text(String(describing: t))
                                Spacer()
                                if t == selectedType { Image(systemName: "checkmark") }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedType = t
                                player.type = t
                                let key = MPDConnectionProperties.MPDType.rawValue + "." + player.uniqueID
                                player.userDefaults.set(t.rawValue, forKey: key)
                                player.objectWillChange.send()
                            }
                        }
                    }
                    .navigationTitle(Text("Type", bundle: .module))
                } label: {
                    HStack {
                        Text("Type", bundle: .module)
                        Spacer()
                        Text(String(describing: selectedType))
                            .foregroundColor(.secondary)
                    }
                }
                #endif

                HStack {
                    Text("Name", bundle: .module)
                    Spacer()
                    // Editable TextField; when empty the original player.name shows as prompt
                    TextField("", text: $customPlayerName, prompt: Text(player.name))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .frame(maxWidth: 220)
                        .popoverTip(changeNameTip)
                        .onChange(of: customPlayerName) { _, newValue in
                            let key = MPDConnectionProperties.customPlayerName.rawValue + "." + player.uniqueID
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                player.userDefaults.removeObject(forKey: key)
                                player.name = player.deviceName
                            } else {
                                player.userDefaults.set(trimmed, forKey: key)
                                player.name = trimmed
                            }
                            player.objectWillChange.send()
                        }
                }

                HStack {
                    Text("Version", bundle: .module)
                    Spacer()
                    Text(player.mpdConnector.version.description)
                        .foregroundColor(.secondary)
                }

                // Host and Port display
                HStack {
                    Text("Host", bundle: .module)
                    Spacer()
                    Text(player.connectionProperties[ConnectionProperties.host.rawValue] as? String ?? "")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Port", bundle: .module)
                    Spacer()
                    if let port = player.connectionProperties[ConnectionProperties.port.rawValue] as? Int {
                        Text("\(port)")
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(localized: "Unknown", bundle: .module))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Advanced Section
            Section(header: Text("Advanced", bundle: .module), footer: Text("If the player is not responding, you can connect directly to it's IP instead. Normally this shall be disabled.", bundle: .module)) {
                HStack {
                    Text(String(localized: "Use IP Address", bundle: .module))
                    Spacer()
                    Toggle("", isOn: $connectToIp)
                        .onChange(of: connectToIp) { _, _ in
                            updateIPAddressSettings()
                        }

                }

                HStack {
                    Text(String(localized: "IP Address to Use", bundle: .module))
                    Spacer()
                    TextField("", text: $ipAddressField)
                        .disabled(connectToIp == false)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .frame(maxWidth: 120)
                        .onChange(of: ipAddressField) { _, _ in
                            updateIPAddressSettings()
                        }
                }
            }

            // HTTP Output Section
            Section(header: Text("HTTP Stream", bundle: .module), footer: Text("If you have configured a http-stream output for mpd, you can enter the ip address and port number here. Rigelian can then play the stream on your local machine.", bundle: .module)) {
                HStack {
                    Text(String(localized: "Host or IP Address", bundle: .module))
                    Spacer()
                    TextField("", text: $outputHostField, prompt: Text("Enter hostname or IP"))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .onChange(of: outputHostField) { _, _ in
                            updateStreamSettings()
                        }
                }
                HStack {
                    Text(String(localized: "Port number", bundle: .module))
                    Spacer()
                    TextField("", text: $outputPortField, prompt: Text("Enter port"))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .onChange(of: outputPortField) { _, _ in
                            updateStreamSettings()
                        }
                }
            }

            // MPD Database Section
            Section(header: Text("MPD Database", bundle: .module)) {
                HStack {
                    Text("Status", bundle: .module)
                    Spacer()
                    Text(databaseStatusText)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Artists", bundle: .module)
                    Spacer()
                    Text(databaseArtists)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Albums", bundle: .module)
                    Spacer()
                    Text(databaseAlbums)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Songs", bundle: .module)
                    Spacer()
                    Text(databaseSongs)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 25){
                    Spacer()

                    Button(String(localized: "Update Database", bundle: .module)) {
                        Task {
                            performingDBAction = true
                            do {
                                if let browse = player.browse as? MPDBrowse {
                                    _ = try await browse.updateDB()
                                    // refresh status and stats
                                    databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                                    // try to fetch stats via status.stats()
                                    if let stats = try? await browse.databaseStats() {
                                        databaseArtists = "\(stats.artists)"
                                        databaseAlbums = "\(stats.albums)"
                                        databaseSongs = "\(stats.songs)"
                                    }
                                }
                            } catch {
                                databaseStatusText = "Error: \(error)"
                            }
                            performingDBAction = false
                        }
                    }

                    Button(String(localized: "Rescan", bundle: .module), role: .destructive) {
                        Task {
                            performingDBAction = true
                            do {
                                if let browse = player.browse as? MPDBrowse {
                                    _ = try await browse.rescanLibrary()
                                    databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                                    if let stats = try? await browse.databaseStats() {
                                        databaseArtists = "\(stats.artists)"
                                        databaseAlbums = "\(stats.albums)"
                                        databaseSongs = "\(stats.songs)"
                                    }
                                }
                            } catch {
                                databaseStatusText = "Error: \(error)"
                            }
                            performingDBAction = false
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            if let browse = player.browse as? MPDBrowse {
                databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                if let stats = try? await browse.databaseStats() {
                    databaseArtists = "\(stats.artists)"
                    databaseAlbums = "\(stats.albums)"
                    databaseSongs = "\(stats.songs)"
                }
            }
        }
    }
    
    func updateStreamSettings() {
        let uid = player.uniqueID
        let ud = player.userDefaults
        if outputHostField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ud.removeObject(forKey: MPDConnectionProperties.outputHost.rawValue + "." + uid)
        } else {
            ud.set(outputHostField, forKey: MPDConnectionProperties.outputHost.rawValue + "." + uid)
        }
        
        if let portInt = Int(outputPortField) {
            ud.set(portInt, forKey: MPDConnectionProperties.outputPort.rawValue + "." + uid)
        } else {
            ud.removeObject(forKey: MPDConnectionProperties.outputPort.rawValue + "." + uid)
        }
        player.objectWillChange.send()
    }
    
    func updateIPAddressSettings() {
        let uid = player.uniqueID
        let ud = player.userDefaults
        if ipAddressField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ud.removeObject(forKey: MPDConnectionProperties.ipAddress.rawValue + "." + uid)
        } else {
            ud.set(ipAddressField, forKey: MPDConnectionProperties.ipAddress.rawValue + "." + uid)
        }
        ud.set(connectToIp, forKey: MPDConnectionProperties.connectToIpAddress.rawValue + "." + uid)
        player.objectWillChange.send()
    }
}

struct MPDChangeNameTip: Tip {
    var id: String { "mpd.changename" }
    var title: Text { Text("Change name") }
    var message: Text? { Text("You can change the player's name that will be displayed in Rigelian.") }
    var image: Image? { Image(systemName: "rectangle.and.pencil.and.ellipsis") }
    var rules: [Self.Rule] { [] }
    var actions: [Self.Action] { [] }
    var options: [any TipOption] { [] }
}

#if DEBUG
struct OpenHomeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        // Note: This preview won't work without a real OpenHomePlayer instance
        // It's provided for structure reference only
        Text("OpenHome Settings Preview")
            .previewDisplayName("OpenHome Settings")
    }
}
#endif

